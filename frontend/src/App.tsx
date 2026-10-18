import '@mantine/core/styles.css';
import '@mantine/notifications/styles.css';
import '@mantine/dates/styles.css';
import 'dayjs/locale/it';
import { useCallback, useEffect, useState } from 'react';
import { Alert, Badge, Button, Container, Group, MantineProvider, Paper, Select, Stack, Tabs, Text, Title } from '@mantine/core';
import { DatesProvider } from '@mantine/dates';
import { Notifications, notifications } from '@mantine/notifications';
import { visibleTabs } from './access.ts';
import { errorMessage, eth, loadAccounts, loadState, shortAddress, writerFor } from './chain';
import type { Account, AppState, Run } from './chain';
import EventsTab from './EventsTab';
import MarketTab from './MartketTab.tsx';
import MyTicketsTab from './MyTicketsTab';
import OrganizerTab from './OrganizerTab';
import PromoterTab from './PromoterTab';

export default function App() {
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [accountIndex, setAccountIndex] = useState(4); // Anna
  const [state, setState] = useState<AppState | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [tab, setTab] = useState('events');

  // 1. All'avvio leggiamo gli account di anvil
  useEffect(() => {
    loadAccounts()
      .then(setAccounts)
      .catch((e) => setError(errorMessage(e)));
  }, []);

  // 2. Leggiamo lo stato del contratto per l'account scelto, e lo aggiorniamo ogni 4 secondi
  const refresh = useCallback(async () => {
    if (accounts.length === 0) return;
    try {
      setState(await loadState(accounts[accountIndex].address));
      setError(null);
    } catch (e) {
      setError(errorMessage(e));
    }
  }, [accounts, accountIndex]);

  useEffect(() => {
    refresh();
    const timer = setInterval(refresh, 4000);
    return () => clearInterval(timer);
  }, [refresh]);

  // 3. Ogni scrittura passa da qui: la firma l'account scelto, la valida il contratto
  const run: Run = async (title, action, successMessage) => {
    try {
      const contract = await writerFor(accountIndex);
      const tx = await action(contract);
      await tx.wait();
      notifications.show({ color: 'green', title, message: successMessage ?? 'Transazione confermata' });
    } catch (e) {
      notifications.show({ color: 'red', title: `${title}: rifiutata`, message: errorMessage(e) });
    }
    await refresh();
  };

  const info = state?.info;

  // Le schede Organizzatore e Promoter le vedono solo organizzatori e promoter (il contratto
  // verifica comunque il ruolo a ogni operazione). Se la scheda aperta sparisce cambiando account,
  // si torna a Eventi.
  const tabs = info ? visibleTabs(info) : ['events'];
  const activeTab = tabs.includes(tab) ? tab : 'events';

  // Se l'indirizzo e uno degli account di anvil mostriamo il nome, altrimenti l'indirizzo abbreviato
  const labelOf = (address: string) =>
    accounts.find((a) => a.address.toLowerCase() === address.toLowerCase())?.label ?? shortAddress(address);

  return (
    <MantineProvider>
      <DatesProvider settings={{ locale: 'it', firstDayOfWeek: 1 }}>
      <Notifications />
      <Container size="lg" py="md">
        <Stack>
          <Group justify="space-between" align="flex-end">
            <Title order={2}>FairTicket</Title>
            <Select
              label="Account"
              allowDeselect={false}
              w={300}
              data={accounts.map((a) => ({ value: String(a.index), label: `${a.label} · ${shortAddress(a.address)}` }))}
              value={String(accountIndex)}
              onChange={(value) => setAccountIndex(Number(value))}
            />
          </Group>

          {error && (
            <Alert color="red" title="Impossibile leggere la blockchain">
              {error}. Controlla che anvil sia acceso, che il deploy sia stato fatto e che l&apos;indirizzo in .env.local
              sia quello giusto.
            </Alert>
          )}

          {info && state && (
            <Paper withBorder p="md">
              <Group justify="space-between">
                <Group>
                  {info.isOrganizer && <Badge color="blue">Organizzatore</Badge>}
                  {info.isPromoter && <Badge color="grape">Promoter</Badge>}
                  {info.isUser && <Badge color="teal">Invitato da {labelOf(info.invitedBy)}</Badge>}
                  {!info.isOrganizer && !info.isPromoter && !info.isUser && <Badge color="gray">Non invitato</Badge>}
                  <Text size="sm">Saldo: {eth(info.balance)} ETH</Text>
                  <Text size="sm">
                    Acquisti: {info.purchased} / {state.limit}
                  </Text>
                </Group>
                {info.pending > 0n && (
                  <Button size="xs" onClick={() => run('Prelievo', (c) => c.withdraw())}>
                    Preleva {eth(info.pending)} ETH
                  </Button>
                )}
              </Group>
            </Paper>
          )}

          {state && (
            <Tabs value={activeTab} onChange={(value) => setTab(value ?? 'events')}>
              <Tabs.List>
                <Tabs.Tab value="events">Eventi</Tabs.Tab>
                <Tabs.Tab value="tickets">I miei biglietti</Tabs.Tab>
                <Tabs.Tab value="market">Mercato</Tabs.Tab>
                {tabs.includes('organizer') && <Tabs.Tab value="organizer">Organizzatore</Tabs.Tab>}
                {tabs.includes('promoter') && <Tabs.Tab value="promoter">Promoter</Tabs.Tab>}
              </Tabs.List>
              <Tabs.Panel value="events" pt="md">
                <EventsTab events={state.events} run={run} />
              </Tabs.Panel>
              <Tabs.Panel value="tickets" pt="md">
                <MyTicketsTab
                  tickets={state.tickets}
                  events={state.events}
                  info={state.info}
                  commissionPercent={state.commissionPercent}
                  run={run}
                />
              </Tabs.Panel>
              <Tabs.Panel value="market" pt="md">
                <MarketTab
                  tickets={state.tickets}
                  events={state.events}
                  accounts={accounts}
                  info={state.info}
                  commissionPercent={state.commissionPercent}
                  run={run}
                />
              </Tabs.Panel>
              {tabs.includes('organizer') && (
                <Tabs.Panel value="organizer" pt="md">
                  <OrganizerTab events={state.events} info={state.info} run={run} />
                </Tabs.Panel>
              )}
              {tabs.includes('promoter') && (
                <Tabs.Panel value="promoter" pt="md">
                  <PromoterTab
                    events={state.events}
                    accounts={accounts}
                    info={state.info}
                    promoterPercent={state.promoterPercent}
                    run={run}
                  />
                </Tabs.Panel>
              )}
            </Tabs>
          )}
        </Stack>
      </Container>
      </DatesProvider>
    </MantineProvider>
  );
}