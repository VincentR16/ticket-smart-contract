import { Badge, Button, Card, Group, Progress, SimpleGrid, Stack, Text } from '@mantine/core';
import { formatEther } from 'ethers';
import type { EventData, Run } from './chain';

interface Props {
  events: EventData[];
  run: Run;
}

export default function EventsTab({ events, run }: Props) {
  if (events.length === 0) {
    return <Text c="dimmed">Nessun evento: creane uno dalla scheda Organizzatore.</Text>;
  }

  return (
    <SimpleGrid cols={{ base: 1, sm: 2 }}>
      {events.map((ev) => {
        const soldOut = ev.sold >= ev.maxSeats;
        const canBuy = !ev.cancelled && !soldOut;

        return (
          <Card key={ev.id} withBorder>
            <Stack gap="xs">
              <Group justify="space-between">
                <Text fw={600}>{ev.name}</Text>
                <Group gap={4}>
                  {ev.cancelled && <Badge color="red">Annullato</Badge>}
                  {!ev.cancelled && soldOut && <Badge color="orange">Sold out</Badge>}
                </Group>
              </Group>

              <Text size="sm" c="dimmed">
                {new Date(ev.date * 1000).toLocaleString('it-IT')}
              </Text>
              <Text>{formatEther(ev.price)} ETH</Text>

              <Progress value={(ev.sold / ev.maxSeats) * 100} />
              <Text size="xs" c="dimmed">
                {ev.sold} / {ev.maxSeats} biglietti venduti
              </Text>

              <Button disabled={!canBuy} onClick={() => run('Acquisto biglietto', (c) => c.buyTicket(ev.id, { value: ev.price }))}>
                Compra
              </Button>
            </Stack>
          </Card>
        );
      })}
    </SimpleGrid>
  );
}