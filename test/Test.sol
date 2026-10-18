// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {FairTicket} from "../src/FairTicket.sol";

contract FairTicketTest is Test {
    FairTicket internal ticket;

    // address(this) ha fatto il deploy: e admin e organizzatore
    address internal promoter = makeAddr("promoter");
    address internal anna = makeAddr("anna"); // invitata dal promoter
    address internal bob = makeAddr("bob"); // invitato dal promoter
    address internal carol = makeAddr("carol"); // non invitata

    uint256 internal constant PRICE = 1 ether;
    uint64 internal eventDate;

    // Serve per incassare come organizzatore (claimRevenue, commissioni, withdraw)
    receive() external payable {}

    function setUp() public {
        ticket = new FairTicket();
        ticket.grantRole(ticket.PROMOTER_ROLE(), promoter);

        // Anna e Bob vengono invitati dal promoter
        vm.startPrank(promoter);
        ticket.inviteUser(anna);
        ticket.inviteUser(bob);
        vm.stopPrank();

        deal(anna, 100 ether);
        deal(bob, 100 ether);
        deal(carol, 100 ether);
        eventDate = uint64(block.timestamp + 1 days);
    }

    // ------------------------------------------------------------ helper

    function _newEventWithSeats(uint32 seats) internal returns (uint256) {
        return ticket.createEvent("Webinar Sicurezza", eventDate, PRICE, seats);
    }

    function _newEvent() internal returns (uint256) {
        return _newEventWithSeats(100);
    }

    function _buy(address who, uint256 eventId) internal returns (uint256 ticketId) {
        vm.prank(who);
        ticketId = ticket.buyTicket{value: PRICE}(eventId);
    }

    // ------------------------------------------------------------- inviti

    function testInviteByPromoter() public {
        vm.prank(promoter);
        ticket.inviteUser(carol);

        assertTrue(ticket.hasRole(ticket.USER_ROLE(), carol));
        assertEq(ticket.invitedBy(carol), promoter);
    }

    function testInviteRestrictions() public {
        address promoter2 = makeAddr("promoter2");
        ticket.grantRole(ticket.PROMOTER_ROLE(), promoter2);
        bytes32 role = ticket.PROMOTER_ROLE();

        // Un utente invitato non puo invitare a sua volta
        vm.prank(anna);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, anna, role));
        ticket.inviteUser(carol);

        // Il promoter invita solo utenti semplici: non un altro promoter, ne un organizzatore
        vm.prank(promoter);
        vm.expectRevert("Cannot invite a role holder");
        ticket.inviteUser(promoter2);

        vm.prank(promoter);
        vm.expectRevert("Cannot invite a role holder");
        ticket.inviteUser(address(this));
    }

    // ------------------------------------------------------------- eventi

    function testCreateEventOnlyOrganizer() public {
        bytes32 role = ticket.ORGANIZER_ROLE();

        // Il promoter puo invitare ma non creare eventi
        vm.prank(promoter);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, promoter, role)
        );
        ticket.createEvent("x", eventDate, PRICE, 10);
    }

    // --------------------------------------------------------- acquisto

    function testBuyTicket() public {
        uint256 eventId = _newEvent();
        uint256 ticketId = _buy(anna, eventId);

        assertEq(ticket.ownerOf(ticketId), anna);
        (,,,, uint32 sold,) = ticket.events(eventId);
        assertEq(uint256(sold), 1);
        assertEq(ticket.maxTickets(anna), 1);
        assertEq(address(ticket).balance, PRICE);
    }

    function testAnyoneCanBuy() public {
        uint256 eventId = _newEvent();

        // Carol non e stata invitata da nessuno: compra lo stesso, e nessun promoter matura commissioni
        uint256 ticketId = _buy(carol, eventId);

        assertEq(ticket.ownerOf(ticketId), carol);
        assertEq(ticket.eventPromoterFees(eventId), 0);
    }

    function testBuyTicketLimitReached() public {
        uint256 limit = ticket.MAX_TICKETS();
        uint256 eventId = _newEventWithSeats(10);

        // Anna compra fino al limite
        for (uint256 i = 0; i < limit; i++) {
            _buy(anna, eventId);
        }

        // Un altro acquisto viene rifiutato
        vm.prank(anna);
        vm.expectRevert("You already purchased 5 tickets");
        ticket.buyTicket{value: PRICE}(eventId);
    }

    // ------------------------------------------------------ trasferimenti

    function testDirectTransferBlocked() public {
        uint256 ticketId = _buy(anna, _newEvent());

        vm.prank(anna);
        vm.expectRevert("Direct transfer not allowed");
        ticket.transferFrom(anna, bob, ticketId);
    }

    function testTransferTicket() public {
        uint256 ticketId = _buy(anna, _newEvent());

        vm.prank(anna);
        ticket.transferTicket(ticketId, bob);

        assertEq(ticket.ownerOf(ticketId), bob);
    }

    // ---------------------------------------------------------- rivendita

    function testResaleWithCommission() public {
        uint256 ticketId = _buy(anna, _newEventWithSeats(2)); // 1 su 2 venduti: tetto +50%
        assertEq(ticket.maxResellPrice(ticketId), 1.5 ether);

        vm.prank(anna);
        ticket.addToResellTicket(ticketId, 1.5 ether);

        vm.prank(bob);
        ticket.buyResellTicket{value: 1.5 ether}(ticketId);

        // Extraprofitto di 0.5 ETH: commissione del 5% (0.025) all'organizzatore
        assertEq(ticket.ownerOf(ticketId), bob);
        assertEq(ticket.pendingWithdrawals(anna), 1.475 ether);
        assertEq(ticket.pendingWithdrawals(address(this)), 0.025 ether);
    }

    function testResaleCapGrowsWithScarcity() public {
        uint256 eventId = _newEventWithSeats(4);
        uint256 ticketId = _buy(anna, eventId); // 1 su 4 venduti
        assertEq(ticket.maxResellPrice(ticketId), 1.25 ether);

        // Sopra il tetto: rifiutato
        vm.prank(anna);
        vm.expectRevert("Price is too high");
        ticket.addToResellTicket(ticketId, 1.25 ether + 1);

        _buy(bob, eventId); // 2 su 4 venduti
        assertEq(ticket.maxResellPrice(ticketId), 1.5 ether);
    }

    // --------------------------------------------- conferma di presenza

    function testConfirmAttendance() public {
        uint256 ticketId = _buy(anna, _newEvent());

        vm.prank(anna);
        ticket.confirmAttendance(ticketId);

        (,,, bool used) = ticket.tickets(ticketId);
        assertTrue(used);
    }

    // ---------------------------------------------------------- rimborsi

    function testCancelAndRefund() public {
        uint256 eventId = _newEvent();
        uint256 ticketId = _buy(anna, eventId); // la commissione del promoter matura ma non esce dal contratto

        ticket.cancelEvent(eventId);

        vm.prank(anna);
        ticket.refundTicket(ticketId);
        assertEq(ticket.pendingWithdrawals(anna), PRICE);

        uint256 before = anna.balance;
        vm.prank(anna);
        ticket.withdraw();

        // Rimborso del prezzo intero e contratto a zero
        assertEq(anna.balance, before + PRICE);
        assertEq(address(ticket).balance, 0);
    }

    // ------------------------------------------- incassi e commissioni

    function testPromoterCommission() public {
        uint256 eventId = _newEvent();
        _buy(anna, eventId);
        _buy(bob, eventId);

        // Il 2% di ogni biglietto comprato da un invitato matura per il promoter
        assertEq(ticket.eventPromoterFees(eventId), 0.04 ether);
        assertEq(ticket.promoterEarned(eventId, promoter), 0.04 ether);

        vm.warp(eventDate + 1);
        vm.prank(promoter);
        ticket.claimPromoterCommission(eventId);
        ticket.claimRevenue(eventId);

        // L'organizzatore incassa il resto: in totale esce esattamente quanto e entrato
        assertEq(ticket.pendingWithdrawals(promoter), 0.04 ether);
        assertEq(ticket.pendingWithdrawals(address(this)), 1.96 ether);
        assertEq(address(ticket).balance, 2 * PRICE);
    }

    function testClaimRevenue() public {
        uint256 eventId = _newEvent();
        _buy(carol, eventId); // non invitata: nessuna commissione
        _buy(bob, eventId); // invitato: 0.02 ETH al promoter

        vm.warp(eventDate + 1);
        ticket.claimRevenue(eventId);

        assertEq(ticket.pendingWithdrawals(address(this)), 1.98 ether);
    }

    function testClaimCancelledReverts() public {
        uint256 eventId = _newEvent();
        _buy(anna, eventId);
        ticket.cancelEvent(eventId);
        vm.warp(eventDate + 1);

        // Evento annullato: ne l'organizzatore ne il promoter possono incassare
        vm.expectRevert("Event cancelled");
        ticket.claimRevenue(eventId);

        vm.prank(promoter);
        vm.expectRevert("Event cancelled");
        ticket.claimPromoterCommission(eventId);
    }
}