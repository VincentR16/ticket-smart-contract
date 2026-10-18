import { useState } from 'react';
import { Badge, Button, Card, Group, Select, Stack, Text, Title } from '@mantine/core';
import { inviteCandidates } from './access';
import { claimPromoterAndWithdraw, eth, shortAddress } from './chain';
import type { Account, AccountInfo, EventData, Run } from './chain';

interface Props {
  events: EventData[];
  accounts: Account[];
  info: AccountInfo;
  promoterPercent: number;
  run: Run;
}

export default function PromoterTab({ events, accounts, info, promoterPercent, run }: Props) {
  const [invitee, setInvitee] = useState<string | null>(null);

  // Gli eventi su cui questo account ha maturato una commissione
  const earned = events.filter((ev) => ev.promoterEarned > 0n);

  return (
    <Stack>
      <Text size="sm" c="dimmed">
        Questa scheda la vedono solo i promoter. Puoi invitare solo utenti semplici, non chi ha già un ruolo. Quando un
        utente che hai invitato compra un biglietto maturi il {promoterPercent}% del prezzo, che incassi a evento finito e
        non annullato. Ruolo e date li verifica il contratto.
      </Text>

      <Card withBorder>
        <Stack gap="xs">
          <Title order={4}>Invita un utente</Title>
          <Select
            label="Account da invitare"
            placeholder="Scegli un account"
            data={inviteCandidates(accounts, info.address).map((a) => ({
              value: a.address,
              label: `${a.label} · ${shortAddress(a.address)}`,
            }))}
            value={invitee}
            onChange={setInvitee}
          />
          <Button disabled={!invitee} onClick={() => invitee && run('Invito', (c) => c.inviteUser(invitee), 'Utente invitato')}>
            Invita
          </Button>
        </Stack>
      </Card>

      <Title order={4}>Le mie commissioni</Title>
      {earned.length === 0 && (
        <Text c="dimmed">Nessuna commissione maturata: compare quando un tuo invitato compra un biglietto.</Text>
      )}
      {earned.map((ev) => (
        <Card key={ev.id} withBorder>
          <Group justify="space-between">
            <div>
              <Group gap="xs">
                <Text fw={600}>{ev.name}</Text>
                {ev.cancelled && <Badge color="red">Annullato</Badge>}
              </Group>
              <Text size="xs" c="dimmed">
                Commissione maturata: {eth(ev.promoterEarned)} ETH
              </Text>
            </div>
            <Button
              disabled={ev.cancelled}
              onClick={() => run('Commissione', (c) => claimPromoterAndWithdraw(c, ev.id), 'Commissione accreditata e prelevata')}
            >
              Incassa commissione
            </Button>
          </Group>
        </Card>
      ))}
    </Stack>
  );
}