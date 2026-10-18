import { useState } from 'react';
import { Badge, Button, Card, Group, NumberInput, SimpleGrid, Stack, Text } from '@mantine/core';
import { formatEther, parseEther } from 'ethers';
import { commissionFor, eth, refundAndWithdraw } from './chain';
import type { AccountInfo, EventData, Run, TicketData } from './chain';

interface Props {
  tickets: TicketData[];
  events: EventData[];
  info: AccountInfo;
  commissionPercent: number;
  run: Run;
}

export default function MyTicketsTab({ tickets, events, info, commissionPercent, run }: Props) {
  const mine = tickets.filter((t) => t.owner.toLowerCase() === info.address.toLowerCase());

  if (mine.length === 0) {
    return <Text c="dimmed">Questo account non possiede biglietti: compra dalla scheda Eventi o dal Mercato.</Text>;
  }

  return (
    <SimpleGrid cols={{ base: 1, sm: 2 }}>
      {mine.map((t) => (
        <TicketCard
          key={t.id}
          ticket={t}
          event={events.find((e) => e.id === t.eventId)}
          commissionPercent={commissionPercent}
          run={run}
        />
      ))}
    </SimpleGrid>
  );
}

interface CardProps {
  ticket: TicketData;
  event?: EventData;
  commissionPercent: number;
  run: Run;
}

function TicketCard({ ticket, event, commissionPercent, run }: CardProps) {
  // Prezzo proposto: parte dal tetto attuale, che sale quando si vendono altri biglietti
  const [price, setPrice] = useState<number | string>(Number(formatEther(ticket.maxPrice)));

  const listed = ticket.resalePrice > 0n;
  const cancelled = event?.cancelled ?? false;
  // Solo lo stato dei dati: se la data e passata lo decide il contratto
  const canList = !ticket.used && !cancelled;
  const canCheckIn = !ticket.used && !cancelled;

  // Anteprima: cosa succede se il biglietto viene venduto a questo prezzo
  let priceWei: bigint | null = null;
  try {
    priceWei = parseEther(String(price));
  } catch {
    priceWei = null;
  }
  const fee = priceWei === null ? 0n : commissionFor(priceWei, ticket.lastPaid, commissionPercent);
  const aboveCap = priceWei !== null && priceWei > ticket.maxPrice;

  return (
    <Card withBorder>
      <Stack gap="xs">
        <Group justify="space-between">
          <Text fw={600}>
            {event?.name ?? `Evento ${ticket.eventId}`} · biglietto #{ticket.id}
          </Text>
          <Group gap={4}>
            {ticket.used && <Badge color="teal">Presenza confermata</Badge>}
            {listed && <Badge color="blue">In vendita a {eth(ticket.resalePrice)} ETH</Badge>}
            {cancelled && <Badge color="red">Evento annullato</Badge>}
          </Group>
        </Group>

        <Text size="xs" c="dimmed">
          Prezzo di listino {eth(ticket.pricePaid)} ETH 
        </Text>

        {listed ? (
          <Button color="red" variant="light" onClick={() => run('Annuncio ritirato', (c) => c.deleteResellTicket(ticket.id))}>
            Togli dalla vendita
          </Button>
        ) : (
          <>
            <NumberInput label="Prezzo di vendita (ETH)" min={0} decimalScale={4} value={price} onChange={setPrice} disabled={!canList} />
     
            <Button disabled={!canList} onClick={() => run('Messa in vendita', (c) => c.addToResellTicket(ticket.id, parseEther(String(price))))}>
              Metti in vendita
            </Button>
          </>
        )}

        {cancelled && (
          <Text size="xs" c="red">
            Evento annullato: rimborso di {eth(ticket.pricePaid)} ETH (prezzo di listino)
            {ticket.lastPaid > ticket.pricePaid ? `. Hai pagato ${eth(ticket.lastPaid)} ETH: la differenza non viene rimborsata.` : '.'}
          </Text>
        )}

        <Group grow>
          <Button variant="light" disabled={!canCheckIn} onClick={() => run('Check-in', (c) => c.confirmAttendance(ticket.id), 'Presenza confermata')}>
            Check-in
          </Button>
          <Button
            color="orange"
            variant="light"
            disabled={!cancelled}
            onClick={() => run('Rimborso', (c) => refundAndWithdraw(c, ticket.id), 'Rimborso accreditato e prelevato')}
          >
            Rimborso
          </Button>
        </Group>
      </Stack>
    </Card>
  );
}