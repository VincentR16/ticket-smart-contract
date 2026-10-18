import { JsonRpcProvider, Contract, ZeroHash, formatEther, id } from 'ethers';
import abi from './abi/FairTicket.json';

export const CONTRACT_ADDRESS = import.meta.env.VITE_CONTRACT_ADDRESS as string;
const RPC_URL = (import.meta.env.VITE_RPC_URL as string | undefined) ?? 'http://127.0.0.1:8545';

// Tipi dei dati che la pagina legge dal contratto
export interface Account {
  index: number;
  label: string;
  address: string;
  hasRole: boolean; // organizzatore, promoter o admin: un promoter non puo invitarlo
}

export interface AccountInfo {
  address: string;
  isOrganizer: boolean;
  isPromoter: boolean;
  isUser: boolean;
  balance: bigint;
  pending: bigint;
  invitedBy: string; // il promoter che ha invitato questo account (indirizzo zero = nessuno)
  purchased: number; // biglietti acquistati finora (conta per il limite)
}

export interface EventData {
  id: number;
  name: string;
  date: number;
  price: bigint;
  maxSeats: number;
  sold: number;
  cancelled: boolean;
  organizer: string;
  revenueClaimed: boolean;
  promoterFees: bigint; // commissioni dei promoter su tutto l'evento
  promoterEarned: bigint; // la commissione maturata dall'account collegato
}

export interface TicketData {
  id: number;
  eventId: number;
  owner: string;
  pricePaid: bigint; // prezzo di listino
  lastPaid: bigint; // ultimo prezzo pagato dal titolare
  used: boolean; // presenza confermata
  resalePrice: bigint; // 0 = non in vendita
  maxPrice: bigint; // tetto di rivendita attuale
}

export interface AppState {
  info: AccountInfo;
  events: EventData[];
  tickets: TicketData[];
  limit: number;
  commissionPercent: number;
  promoterPercent: number;
}

// Una scrittura: la pagina passa una funzione che riceve il contratto collegato
// all'account scelto e restituisce la transazione da inviare.
export type Run = (
  title: string,
  action: (contract: Contract) => Promise<{ wait: () => Promise<unknown> }>,
  successMessage?: string
) => Promise<void>;

// cacheTimeout: -1 disattiva la cache di ethers (250 ms): dopo una transazione
// vogliamo leggere subito il valore aggiornato, non quello di un istante fa.
export const provider = new JsonRpcProvider(RPC_URL, undefined, { cacheTimeout: -1 });

// Contratto in sola lettura: per leggere non serve nessun account.
export const reader = new Contract(CONTRACT_ADDRESS, abi, provider);

// Gli identificatori dei ruoli sono keccak256("NOME"), come nel contratto.
const ORGANIZER_ROLE = id('ORGANIZER_ROLE');
const PROMOTER_ROLE = id('PROMOTER_ROLE');
const USER_ROLE = id('USER_ROLE');

// Gli account di anvil, nell'ordine in cui lo script di deploy assegna i ruoli.
const ACCOUNT_LABELS = [
  'Organizzatore 1 (admin)',
  'Organizzatore 2',
  'Promoter 1',
  'Promoter 2',
  'Anna',
  'Bob',
  'Carlo',
  'Dario',
  'Elena',
  'Fabio',
];

export async function loadAccounts(): Promise<Account[]> {
  // anvil mette a disposizione i suoi account gia sbloccati: possono firmare senza wallet.
  const signers = await provider.listAccounts();
  return Promise.all(
    ACCOUNT_LABELS.map(async (label, index) => {
      const address = signers[index].address;
      // ZeroHash e l'identificatore del ruolo admin (DEFAULT_ADMIN_ROLE)
      const [organizer, promoter, admin] = await Promise.all([
        reader.hasRole(ORGANIZER_ROLE, address),
        reader.hasRole(PROMOTER_ROLE, address),
        reader.hasRole(ZeroHash, address),
      ]);
      return { index, label, address, hasRole: organizer || promoter || admin };
    })
  );
}

// Per scrivere sulla blockchain serve un contratto collegato a un account che firma.
export async function writerFor(accountIndex: number): Promise<Contract> {
  const signer = await provider.getSigner(accountIndex);
  return new Contract(CONTRACT_ADDRESS, abi, signer);
}

async function loadAccountInfo(address: string): Promise<AccountInfo> {
  const [isOrganizer, isPromoter, isUser, balance, pending, invitedBy, purchased] = await Promise.all([
    reader.hasRole(ORGANIZER_ROLE, address),
    reader.hasRole(PROMOTER_ROLE, address),
    reader.hasRole(USER_ROLE, address),
    provider.getBalance(address),
    reader.pendingWithdrawals(address),
    reader.invitedBy(address),
    reader.maxTickets(address),
  ]);
  return {
    address,
    isOrganizer,
    isPromoter,
    isUser,
    balance,
    pending,
    invitedBy,
    purchased: Number(purchased),
  };
}

// I mapping non si possono scorrere: la lista degli eventi si ricostruisce dai log EventCreated.
async function loadEvents(address: string): Promise<EventData[]> {
  const logs = await reader.queryFilter(reader.filters.EventCreated());
  return Promise.all(
    logs.map(async (log) => {
      const eventId = (log as unknown as { args: { eventId: bigint } }).args.eventId;
      const [ev, organizer, claimed, promoterFees, promoterEarned] = await Promise.all([
        reader.events(eventId),
        reader.eventOrganizer(eventId),
        reader.revenueClaimed(eventId),
        reader.eventPromoterFees(eventId),
        reader.promoterEarned(eventId, address),
      ]);
      return {
        id: Number(eventId),
        name: ev[0],
        date: Number(ev[1]),
        price: ev[2],
        maxSeats: Number(ev[3]),
        sold: Number(ev[4]),
        cancelled: ev[5],
        organizer,
        revenueClaimed: claimed,
        promoterFees,
        promoterEarned,
      };
    })
  );
}

// Gli id dei biglietti si ricostruiscono dai log TicketPurchased; poi si legge lo stato di ciascuno.
async function loadTickets(): Promise<TicketData[]> {
  const logs = await reader.queryFilter(reader.filters.TicketPurchased());
  const tickets = await Promise.all(
    logs.map(async (log): Promise<TicketData | null> => {
      const ticketId = (log as unknown as { args: { ticketId: bigint } }).args.ticketId;
      try {
        const [owner, t, resalePrice, maxPrice] = await Promise.all([
          reader.ownerOf(ticketId),
          reader.tickets(ticketId),
          reader.resellTickets(ticketId),
          reader.maxResellPrice(ticketId),
        ]);
        return { id: Number(ticketId), eventId: Number(t[0]), owner, pricePaid: t[1], lastPaid: t[2], used: t[3], resalePrice, maxPrice };
      } catch (e) {
        // ownerOf fallisce per un biglietto distrutto (rimborsato): lo saltiamo
        if ((e as { code?: string }).code === 'CALL_EXCEPTION') return null;
        throw e;
      }
    })
  );
  return tickets.filter((t): t is TicketData => t !== null);
}

// Tutto cio che la pagina mostra, letto in un colpo solo.
export async function loadState(address: string): Promise<AppState> {
  const [info, events, tickets, limit, commissionPercent, promoterPercent] = await Promise.all([
    loadAccountInfo(address),
    loadEvents(address),
    loadTickets(),
    reader.MAX_TICKETS(),
    reader.COMMISSION_PERCENT(),
    reader.PROMOTER_COMMISSION_PERCENT(),
  ]);
  return {
    info,
    events,
    tickets,
    limit: Number(limit),
    commissionPercent: Number(commissionPercent),
    promoterPercent: Number(promoterPercent),
  };
}

const KNOWN_ERRORS: Record<string, string> = {
  AccessControlUnauthorizedAccount: 'Questo account non ha il ruolo necessario per questa azione',
  ERC721NonexistentToken: 'Biglietto inesistente',
  ReentrancyGuardReentrantCall: 'Chiamata annidata rifiutata',
};

interface EthersError {
  reason?: string | null;
  revert?: { name: string } | null;
  info?: { error?: { message?: string } };
  error?: { message?: string };
  shortMessage?: string;
  message?: string;
}

// Il contratto spiega perche rifiuta una transazione: mostriamo quel messaggio.
export function errorMessage(error: unknown): string {
  const e = error as EthersError;

  // Caso normale: ethers ha decodificato il motivo (stringa o errore personalizzato).
  if (e.reason) return e.reason;
  if (e.revert?.name) return KNOWN_ERRORS[e.revert.name] ?? e.revert.name;

  // Alcuni nodi non restituiscono i dati dell'errore: il motivo e nel testo del messaggio.
  const nodeMessage = e.info?.error?.message ?? e.error?.message ?? '';
  const match = nodeMessage.match(/revert(?:ed)?:?\s+(.+)$/i);
  if (match && !match[1].startsWith('custom error')) return match[1];
  if (/revert/i.test(nodeMessage)) return 'Operazione rifiutata dal contratto';

  return e.shortMessage ?? e.message ?? 'Errore sconosciuto';
}

// Rimborso in un solo passo: il contratto accredita il rimborso (prima transazione)
// e subito dopo lo preleviamo (seconda), cosi i soldi arrivano sull'account.
export async function refundAndWithdraw(contract: Contract, ticketId: number) {
  await (await contract.refundTicket(ticketId)).wait();
  return contract.withdraw();
}

// Incasso dell'organizzatore in un solo passo: accredito e prelievo di seguito.
export async function claimAndWithdraw(contract: Contract, eventId: number) {
  await (await contract.claimRevenue(eventId)).wait();
  return contract.withdraw();
}

// Commissione del promoter in un solo passo: accredito e prelievo di seguito.
export async function claimPromoterAndWithdraw(contract: Contract, eventId: number) {
  await (await contract.claimPromoterCommission(eventId)).wait();
  return contract.withdraw();
}

// Il selettore di data e ora di Mantine lavora con stringhe "AAAA-MM-GG HH:mm:ss" (ora locale).
// Sono solo conversioni di formato: se la data e nel passato lo dice il contratto.
export function toPickerValue(date: Date): string {
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}:00`;
}

export function pickerValueToTimestamp(value: string): number {
  // Safari non legge "AAAA-MM-GG HH:mm:ss" con lo spazio: serve la "T"
  return Math.floor(new Date(value.replace(' ', 'T')).getTime() / 1000);
}

// Un importo in wei mostrato in ETH, con 4 decimali
export const eth = (wei: bigint) => Number(formatEther(wei)).toFixed(4);

// Stessa formula del contratto: la commissione e una percentuale dell'extraprofitto
// del venditore (prezzo di vendita meno quanto ha pagato lui), mai negativa.
export function commissionFor(price: bigint, lastPaid: bigint, percent: number): bigint {
  return price > lastPaid ? ((price - lastPaid) * BigInt(percent)) / 100n : 0n;
}

export function shortAddress(address: string): string {
  return `${address.slice(0, 6)}…${address.slice(-4)}`;
}