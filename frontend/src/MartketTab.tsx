import { Badge, Button, Card, Group, SimpleGrid, Stack, Text } from '@mantine/core';
import { commissionFor, eth, shortAddress } from './chain';
import type { Account, AccountInfo, EventData, Run, TicketData } from './chain';

interface Props {
  tickets: TicketData[];
  events: EventData[];
  accounts: Account[];
  info: AccountInfo;
  commissionPercent: number;
  run: Run;
}

export default function MarketTab({ tickets, events, accounts, info, commissionPercent, run }: Props) {
  const listings = tickets.filter((t) => t.resalePrice > 0n);

  if (listings.length === 0) {
    return <Text c="dimmed">Nessun biglietto in vendita.</Text>;
  }

  // Se l'indirizzo e uno degli account di anvil mostriamo il nome, altrimenti l'indirizzo abbreviato
  const nameOf = (address: string) =>
    accounts.find((a) => a.address.toLowerCase() === address.toLowerCase())?.label ?? shortAddress(address);

  return (
    <SimpleGrid cols={{ base: 1, sm: 2 }}>
      {listings.map((t) => {
        const event = events.find((e) => e.id === t.eventId);
        const isMine = t.owner.toLowerCase() === info.address.toLowerCase();
        const cancelled = event?.cancelled ?? false;
        const canBuy = !isMine && !cancelled && !t.used;

        const fee = commissionFor(t.resalePrice, t.lastPaid, commissionPercent);
        const markup = t.resalePrice >= t.pricePaid ? Number(((t.resalePrice - t.pricePaid) * 100n) / t.pricePaid) : 0;

        return (
          <Card key={t.id} withBorder>
            <Stack gap="xs">
              <Group justify="space-between">
                <Text fw={600}>
                  {event?.name ?? `Evento ${t.eventId}`} · biglietto #{t.id}
                </Text>
                <Group gap={4}>
                  {isMine && <Badge color="blue">Tuo annuncio</Badge>}
                  {cancelled && <Badge color="red">Annullato</Badge>}
                </Group>
              </Group>

              {event && (
                <Text size="sm" c="dimmed">
                  {new Date(event.date * 1000).toLocaleString('it-IT')}
                </Text>
              )}
              <Text>
                {eth(t.resalePrice)} ETH{' '}
                <Text span size="sm" c="dimmed">
                  (listino {eth(t.pricePaid)} ETH, +{markup}%)
                </Text>
              </Text>
              <Text size="xs" c="dimmed">
                Venduto da {nameOf(t.owner)} · incassa {eth(t.resalePrice - fee)} ETH, all&apos;organizzatore vanno {eth(fee)} ETH
              </Text>

              <Button disabled={!canBuy} onClick={() => run('Acquisto in rivendita', (c) => c.buyResellTicket(t.id, { value: t.resalePrice }))}>
                Compra
              </Button>
            </Stack>
          </Card>
        );
      })}
    </SimpleGrid>
  );
}