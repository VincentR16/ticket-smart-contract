# FairTicket

Smart contract per la vendita di biglietti di eventi digitali, con una piccola interfaccia web.
Progetto per il corso di Sicurezza dei Dati (Università degli Studi di Salerno).

Ogni biglietto è un NFT (ERC-721). Gli **organizzatori** creano gli eventi, i **promoter** invitano gli utenti e guadagnano una commissione, e chiunque può comprare e rivendere i biglietti entro un tetto di prezzo.

**Stack:** Solidity 0.8.24 · Foundry · OpenZeppelin 5 · React + TypeScript · Mantine · ethers v6

## Cosa serve

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (`forge` e `anvil`)
- [Node.js](https://nodejs.org) 20.19 o più recente
- Git

## Come farlo partire

Servono due terminali.

**1. Scarica il progetto** (l'opzione `--recurse-submodules` serve per le librerie in `lib/`):

```bash
git clone --recurse-submodules https://github.com/VincentR16/ticket-smart-contract.git
cd ticket-smart-contract
```

**2. Terminale 1: accendi la blockchain locale** e lascialo aperto:

```bash
anvil
```

**3. Terminale 2: pubblica il contratto** (dalla cartella del progetto):

```bash
forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

Deve finire con `ONCHAIN EXECUTION COMPLETE & SUCCESSFUL` (9 transazioni). Quella chiave è l'account 0 di `anvil`, nota a tutti: va bene solo in locale.

**4. Indica alla pagina dove si trova il contratto e avviala:**

```bash
cd frontend
echo 'VITE_CONTRACT_ADDRESS=0x5FbDB2315678afecb367f032d93F642f64180aa3' > .env.local
npm install
npm run dev
```

Apri **http://localhost:5173**.

> Ogni volta che riavvii `anvil` la blockchain riparte da zero: rifai il passo 3 e ricarica la pagina.
> L'indirizzo del contratto è sempre quello sopra se fai il deploy su un `anvil` appena acceso.

## Test

```bash
forge test -vvv
```

## Gli account della demo

La pagina usa gli account di `anvil`: scegli quello da usare dal menu in alto, senza wallet.

| Account | Ruolo |
|---|---|
| Organizzatore 1 (admin), Organizzatore 2 | creano e annullano eventi, incassano |
| Promoter 1, Promoter 2 | invitano utenti, guadagnano il 2% |
| Anna, Bob, Carlo | invitati dal Promoter 1 |
| Dario, Elena | invitati dal Promoter 2 |
| Fabio | non invitato (compra lo stesso, nessun promoter guadagna) |

## Provalo in 5 passi

1. **Organizzatore 1** → scheda *Organizzatore* → crea un evento che inizia tra pochi minuti.
2. **Anna** compra un biglietto da *Eventi*; **Fabio** ne compra un altro.
3. **Anna** fa il *Check-in* oppure lo mette in vendita da *I miei biglietti*; **Bob** lo compra dal *Mercato*.
4. Quando l'evento è iniziato, **Organizzatore 1** e **Promoter 1** premono *Incassa*: i soldi arrivano subito sul conto.
5. Crea un secondo evento e annullalo: chi ha un biglietto preme *Rimborso*.

Le date le controlla solo il contratto: la pagina non può spostare il tempo, quindi per incassare bisogna aspettare davvero l'inizio dell'evento.

## Regole del contratto

- **Acquisto libero**: compra chiunque, fino a 5 biglietti per indirizzo.
- **Inviti**: solo i promoter invitano, e solo utenti semplici (non chi ha già un ruolo).
- **Commissione del promoter**: 2% del prezzo dei biglietti comprati dai suoi invitati. Si incassa a evento finito e viene tolta all'incasso dell'organizzatore.
- **Rivendita**: il prezzo massimo parte dal listino e sale fino al doppio man mano che l'evento si riempie. L'organizzatore prende il 5% dell'eventuale guadagno del venditore.
- **Check-in**: chi lo fa non può più cedere né rivendere il biglietto.
- **Annullamento**: ogni titolare può farsi rimborsare il prezzo di listino.
- **Soldi al sicuro**: nessuno incassa prima della fine dell'evento, i pagamenti passano da un saldo da prelevare (`withdraw`) e le funzioni che muovono soldi sono protette dalla reentrancy.

## Limiti noti

- Il limite di 5 biglietti si aggira con più indirizzi, con una cessione o con una rivendita.
- Un promoter può invitare un proprio secondo indirizzo e comprare da lì, facendosi tornare il 2%.
- Chi compra in rivendita, se l'evento viene annullato, riceve solo il prezzo di listino.
- La pagina firma con gli account sbloccati di `anvil`: è una demo locale. In produzione servirebbe un wallet (per esempio MetaMask).

## Struttura

```
src/FairTicket.sol      il contratto
test/                   test Foundry
script/Deploy.s.sol     deploy e configurazione della demo
frontend/               interfaccia React + Mantine
```
