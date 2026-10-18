// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {FairTicket} from "../src/FairTicket.sol";

/// Deploy e configurazione iniziale per la demo su anvil.
///
/// Account di anvil:
///   0      organizzatore 1 + admin (chi fa il deploy, ruoli assegnati dal costruttore)
///   1      organizzatore 2
///   2, 3   promoter 1 e 2
///   4,5,6  Anna, Bob, Carlo: invitati dal promoter 1
///   7,8    Dario, Elena: invitati dal promoter 2
///   9      Fabio: non invitato (puo comprare, ma nessun promoter matura commissioni)
contract Deploy is Script {
    address internal constant ORGANIZER_2 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; // account 1
    address internal constant PROMOTER_1 = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC; // account 2
    address internal constant PROMOTER_2 = 0x90F79bf6EB2c4f870365E785982E1f101E93b906; // account 3

    address internal constant ANNA = 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65; // account 4
    address internal constant BOB = 0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc; // account 5
    address internal constant CARLO = 0x976EA74026E726554dB657fA54763abd0C3a0aa9; // account 6
    address internal constant DARIO = 0x14dC79964da2C08b23698B3D3cc7Ca32193d9955; // account 7
    address internal constant ELENA = 0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f; // account 8

    // Chiavi note di anvil (account 2 e 3): servono solo in locale, per firmare gli inviti
    // come promoter. Non usarle mai su una rete vera.
    uint256 internal constant PROMOTER_1_KEY = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
    uint256 internal constant PROMOTER_2_KEY = 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6;

    function run() external {
        // 1. Account 0 (quello della chiave passata allo script): deploy e ruoli
        vm.startBroadcast();

        FairTicket ticket = new FairTicket();

        ticket.grantRole(ticket.ORGANIZER_ROLE(), ORGANIZER_2);
        ticket.grantRole(ticket.PROMOTER_ROLE(), PROMOTER_1);
        ticket.grantRole(ticket.PROMOTER_ROLE(), PROMOTER_2);

        vm.stopBroadcast();

        // 2. Il promoter 1 invita Anna, Bob e Carlo
        vm.startBroadcast(PROMOTER_1_KEY);
        ticket.inviteUser(ANNA);
        ticket.inviteUser(BOB);
        ticket.inviteUser(CARLO);
        vm.stopBroadcast();

        // 3. Il promoter 2 invita Dario ed Elena
        vm.startBroadcast(PROMOTER_2_KEY);
        ticket.inviteUser(DARIO);
        ticket.inviteUser(ELENA);
        vm.stopBroadcast();

        console.log("FairTicket deployed at", address(ticket));
    }
}