# FairTicket

Smart contract for selling tickets to digital events, with a small web interface.
Project for the Data Security course (*Sicurezza dei Dati*) at the University of Salerno.

Every ticket is an NFT (ERC-721). **Organizers** create events, **promoters** invite users and earn a commission, and anyone can buy and resell tickets within a price cap.

**Stack:** Solidity 0.8.24 · Foundry · OpenZeppelin 5 · React + TypeScript · Mantine · ethers v6

## Requirements

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (`forge` and `anvil`)
- [Node.js](https://nodejs.org) 20.19 or newer
- Git

## Getting started

You need two terminals.

**1. Clone the project** (`--recurse-submodules` is needed for the libraries in `lib/`):

```bash
git clone --recurse-submodules https://github.com/VincentR16/ticket-smart-contract.git
cd ticket-smart-contract
```

**2. Terminal 1: start the local blockchain** and leave it running:

```bash
anvil
```

**3. Terminal 2: deploy the contract** (from the project folder):

```bash
forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

It must end with `ONCHAIN EXECUTION COMPLETE & SUCCESSFUL` (9 transactions). That key is account 0 of `anvil`, publicly known: it is fine for local use only.

**4. Tell the web page where the contract is and start it:**

```bash
cd frontend
echo 'VITE_CONTRACT_ADDRESS=0x5FbDB2315678afecb367f032d93F642f64180aa3' > .env.local
npm install
npm run dev
```

Open **http://localhost:5173**.

> Every time you restart `anvil` the blockchain starts from scratch: repeat step 3 and reload the page.
> The contract address is always the one above if you deploy on a freshly started `anvil`.

## Tests

```bash
forge test -vvv
```

## Demo accounts

The page uses the `anvil` accounts: pick the one to act as from the menu at the top, no wallet needed. The interface is in Italian, so the labels are shown as they appear on the page.

| Account | Role |
|---|---|
| Organizzatore 1 (admin), Organizzatore 2 | organizers: create and cancel events, collect revenue |
| Promoter 1, Promoter 2 | promoters: invite users, earn 2% |
| Anna, Bob, Carlo | invited by Promoter 1 |
| Dario, Elena | invited by Promoter 2 |
| Fabio | not invited (can still buy, no promoter earns anything) |

## Try it in 5 steps

Tab names are in Italian: *Eventi* (events), *I miei biglietti* (my tickets), *Mercato* (market), *Organizzatore* (organizer), *Promoter*.

1. **Organizzatore 1** → *Organizzatore* tab → create an event starting in a few minutes.
2. **Anna** buys a ticket from *Eventi*; **Fabio** buys another one.
3. **Anna** does the *Check-in*, or lists a ticket for sale from *I miei biglietti*; **Bob** buys it from *Mercato*.
4. Once the event has started, **Organizzatore 1** and **Promoter 1** press *Incassa* (collect): the money goes straight to their balance.
5. Create a second event and cancel it: ticket holders press *Rimborso* (refund).

Dates are checked only by the contract: the page cannot move time forward, so to collect revenue you have to actually wait for the event to start.

## Contract rules

- **Open purchase**: anyone can buy, up to 5 tickets per address.
- **Invitations**: only promoters can invite, and only plain users (not accounts that already hold a role).
- **Promoter commission**: 2% of the price of tickets bought by the users they invited. It is collected after the event and deducted from the organizer's revenue.
- **Resale**: the maximum price starts at the list price and grows up to double as the event fills up. The organizer takes 5% of the seller's profit, if any.
- **Check-in**: once done, the ticket can no longer be transferred or resold.
- **Cancellation**: every holder can get the list price back.
- **Funds are safe**: nobody can collect before the event ends, payments go through a withdrawable balance (`withdraw`), and the functions that move money are protected against reentrancy.

## Known limitations

- The 5-ticket limit can be bypassed with multiple addresses, a transfer or a resale.
- A promoter can invite a second address of their own and buy from it, getting the 2% back.
- Someone who buys in a resale and then sees the event cancelled only gets the list price back.
- The page signs with the unlocked `anvil` accounts: it is a local demo. A real deployment would need a wallet (for example MetaMask).

## Structure

```
src/FairTicket.sol      the contract
test/                   Foundry tests
script/Deploy.s.sol     deploy and demo setup
frontend/               React + Mantine interface
```
