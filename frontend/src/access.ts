import type { Account, AccountInfo } from './chain';

// Le schede che l'account collegato puo vedere: Organizzatore solo agli organizzatori,
// Promoter solo ai promoter. Sono comodita: i permessi veri li controlla il contratto.
export function visibleTabs(info: Pick<AccountInfo, 'isOrganizer' | 'isPromoter'>): string[] {
  const tabs = ['events', 'tickets', 'market'];
  if (info.isOrganizer) tabs.push('organizer');
  if (info.isPromoter) tabs.push('promoter');
  return tabs;
}

// Chi un promoter puo invitare: solo utenti semplici, non se stesso ne chi ha gia un ruolo.
export function inviteCandidates(accounts: Account[], myAddress: string): Account[] {
  return accounts.filter((a) => !a.hasRole && a.address.toLowerCase() !== myAddress.toLowerCase());
}