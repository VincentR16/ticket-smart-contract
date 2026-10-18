import { useState } from 'react';
import { Badge, Button, Card, Group, NumberInput, Stack, Text, TextInput, Title } from '@mantine/core';
import { DateTimePicker } from '@mantine/dates';
import { formatEther, parseEther } from 'ethers';
import { claimAndWithdraw, pickerValueToTimestamp, toPickerValue } from './chain';
import type { AccountInfo, EventData, Run } from './chain';

interface Props {
  events: EventData[];
  info: AccountInfo;
  run: Run;
}

export default function OrganizerTab({ events, info, run }: Props) {
  const [name, setName] = useState('Webinar Sicurezza');
  // Data e ora di inizio: valore iniziale tra 3 minuti, poi la sceglie l'utente
  const [start, setStart] = useState<string | null>(() => toPickerValue(new Date(Date.now() + 3 * 60_000)));
  const [price, setPrice] = useState<number | string>(0.1);
  const [seats, setSeats] = useState(4);

  const mine = events.filter((ev) => ev.organizer.toLowerCase() === info.address.toLowerCase());

  // La pagina invia la data scelta e basta: se e nel passato risponde il contratto.
  const create = () =>
    run('Creazione evento', (c) => {
      if (!start) throw new Error('Scegli data e ora di inizio');
      return c.createEvent(name, BigInt(pickerValueToTimestamp(start)), parseEther(String(price)), seats);
    });

  return (
    <Stack>
      <Text size="sm" c="dimmed">
        Questa scheda la vedono solo gli organizzatori, che possono creare e annullare eventi. Il ruolo lo verifica comunque
        il contratto a ogni operazione, e lo stesso vale per le date: la pagina non le controlla.
      </Text>

      <Card withBorder>
        <Stack gap="xs">
          <Title order={4}>Nuovo evento</Title>
          <TextInput label="Nome" value={name} onChange={(e) => setName(e.currentTarget.value)} />
          <Group grow>
            <DateTimePicker label="Inizia il" valueFormat="DD/MM/YYYY HH:mm" value={start} onChange={setStart} />
            <NumberInput label="Prezzo (ETH)" min={0} decimalScale={4} value={price} onChange={setPrice} />
            <NumberInput label="Posti" min={1} value={seats} onChange={(v) => setSeats(Number(v))} />
          </Group>
          <Button onClick={create}>Crea evento</Button>
        </Stack>
      </Card>

      <Title order={4}>I miei eventi</Title>
      {mine.length === 0 && <Text c="dimmed">Questo account non ha creato eventi.</Text>}
      {mine.map((ev) => {
        // Solo lo stato dei dati: se l'evento e gia iniziato o finito lo decide il contratto
        const canCancel = !ev.cancelled;
        const canClaim = !ev.cancelled && !ev.revenueClaimed;

        return (
          <Card key={ev.id} withBorder>
            <Group justify="space-between">
              <div>
                <Group gap="xs">
                  <Text fw={600}>{ev.name}</Text>
                  {ev.cancelled && <Badge color="red">Annullato</Badge>}
                  {ev.revenueClaimed && <Badge color="green">Incassato</Badge>}
                </Group>
                <Text size="xs" c="dimmed">
                  {ev.sold} / {ev.maxSeats} venduti · incasso previsto {formatEther(ev.price * BigInt(ev.sold) - ev.promoterFees)} ETH
                  {ev.promoterFees > 0n ? ` (dopo ${formatEther(ev.promoterFees)} ETH di commissioni ai promoter)` : ''}
                </Text>
              </div>
              <Group>
                <Button color="red" variant="light" disabled={!canCancel} onClick={() => run('Annullamento', (c) => c.cancelEvent(ev.id))}>
                  Annulla
                </Button>
                <Button disabled={!canClaim} onClick={() => run('Incasso', (c) => claimAndWithdraw(c, ev.id), 'Incasso accreditato e prelevato')}>
                  Incassa
                </Button>
              </Group>
            </Group>
          </Card>
        );
      })}
    </Stack>
  );
}