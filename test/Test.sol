// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {FairTicket} from "../src/FairTicket.sol";

contract FairTicketTest is Test {
    FairTicket internal ticket;

    // address(this) ha fatto il deploy: e admin e organizzatore
    address internal steward = makeAddr("steward");
    address internal anna = makeAddr("anna");
    address internal bob = makeAddr("bob");

    uint256 internal constant PRICE = 1 ether;
    uint64 internal eventDate;

    // Serve per incassare come organizzatore (claimRevenue + withdraw)
    receive() external payable {}

    function setUp() public {
        ticket = new FairTicket();
        ticket.grantRole(ticket.STEWARD_ROLE(), steward);
        deal(anna, 10 ether);
        deal(bob, 10 ether);
        eventDate = uint64(block.timestamp + 1 days);
    }

    // ------------------------------------------------------------ helper

    function _newEvent() internal returns (uint256) {
        return ticket.createEvent("Napoli-Inter", eventDate, PRICE, 100);
    }

    function _buy(address who, uint256 eventId) internal returns (uint256 ticketId) {
        vm.prank(who);
        ticketId = ticket.buyTicket{value: PRICE}(eventId);
    }

    // ------------------------------------------------------- createEvent

    function testCreateEvent() public {
        uint256 eventId = _newEvent();

        (, uint64 date, uint256 price, uint32 maxSeats, uint32 sold, bool cancelled) = ticket.events(eventId);
        assertEq(eventId, 1);
        assertEq(uint256(date), uint256(eventDate));
        assertEq(price, PRICE);
        assertEq(uint256(maxSeats), 100);
        assertEq(uint256(sold), 0);
        assertFalse(cancelled);
        assertEq(ticket.eventOrganizer(eventId), address(this));
    }

    function testCreateEventOnlyOrganizer() public {
        bytes32 role = ticket.ORGANIZER_ROLE();

        vm.prank(anna);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, anna, role));
        ticket.createEvent("x", eventDate, PRICE, 10);
    }

    // --------------------------------------------------------- buyTicket

    function testBuyTicket() public {
        uint256 eventId = _newEvent();
        uint256 ticketId = _buy(anna, eventId);

        assertEq(ticket.ownerOf(ticketId), anna);
        (,,,, uint32 sold,) = ticket.events(eventId);
        assertEq(uint256(sold), 1);
        assertEq(address(ticket).balance, PRICE);
    }

    function testBuyTicketWrongPriceReverts() public {
        uint256 eventId = _newEvent();

        vm.prank(anna);
        vm.expectRevert("Prezzo errato");
        ticket.buyTicket{value: 0.5 ether}(eventId);
    }

    function testBuyTicketSoldOutReverts() public {
        uint256 eventId = ticket.createEvent("x", eventDate, PRICE, 1);
        _buy(anna, eventId);

        vm.prank(bob);
        vm.expectRevert("Sold out");
        ticket.buyTicket{value: PRICE}(eventId);
    }

    function testBuyTicketAfterStartReverts() public {
        uint256 eventId = _newEvent();
        vm.warp(eventDate + 1);

        vm.prank(anna);
        vm.expectRevert("Evento iniziato");
        ticket.buyTicket{value: PRICE}(eventId);
    }

    // ---------------------------------------------- trasferimenti diretti

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

    function testResale() public {
        uint256 ticketId = _buy(anna, _newEvent());
        uint256 maxPrice = ticket.maxResellPrice(ticketId);
        assertEq(maxPrice, 1.25 ether);

        vm.prank(anna);
        ticket.addToResellTicket(ticketId, maxPrice);

        vm.prank(bob);
        ticket.buyResellTicket{value: maxPrice}(ticketId);

        assertEq(ticket.ownerOf(ticketId), bob);
        assertEq(ticket.resellTickets(ticketId), 0);
        assertEq(ticket.pendingWithdrawals(anna), maxPrice);

        uint256 before = anna.balance;
        vm.prank(anna);
        ticket.withdraw();

        assertEq(anna.balance, before + maxPrice);
        assertEq(ticket.pendingWithdrawals(anna), 0);
    }

    function testResaleAboveCapReverts() public {
        uint256 ticketId = _buy(anna, _newEvent());

        vm.prank(anna);
        vm.expectRevert("Price is too high");
        ticket.addToResellTicket(ticketId, 1.25 ether + 1);
    }

    // ------------------------------------------------------------ check-in

    function testCheckIn() public {
        uint256 ticketId = _buy(anna, _newEvent());

        vm.prank(steward);
        ticket.checkIn(ticketId);

        (,, bool used) = ticket.tickets(ticketId);
        assertTrue(used);
    }

    function testUsedTicketCannotBeTransferred() public {
        uint256 ticketId = _buy(anna, _newEvent());
        vm.prank(steward);
        ticket.checkIn(ticketId);

        vm.prank(anna);
        vm.expectRevert("Ticket already used");
        ticket.transferTicket(ticketId, bob);
    }

    // -------------------------------------------- annullamento e rimborsi

    function testCancelAndRefund() public {
        uint256 eventId = _newEvent();
        uint256 ticketId = _buy(anna, eventId);

        ticket.cancelEvent(eventId);

        vm.prank(anna);
        ticket.refundTicket(ticketId);
        assertEq(ticket.pendingWithdrawals(anna), PRICE);

        // il biglietto e stato distrutto
        vm.expectRevert();
        ticket.ownerOf(ticketId);

        uint256 before = anna.balance;
        vm.prank(anna);
        ticket.withdraw();

        assertEq(anna.balance, before + PRICE);
        assertEq(address(ticket).balance, 0);
    }

    function testOtherOrganizerCannotCancel() public {
        uint256 eventId = _newEvent();
        ticket.grantRole(ticket.ORGANIZER_ROLE(), bob);

        vm.prank(bob);
        vm.expectRevert("Non organizzatore dell evento");
        ticket.cancelEvent(eventId);
    }

    function testPendingBalanceIsNotOverwritten() public {
        uint256 event1 = _newEvent();
        uint256 event2 = _newEvent();
        uint256 ticketA = _buy(anna, event1);
        uint256 ticketB = _buy(anna, event2);

        // Anna rivende A a Bob e guadagna 1.25 ETH da prelevare
        vm.prank(anna);
        ticket.addToResellTicket(ticketA, 1.25 ether);
        vm.prank(bob);
        ticket.buyResellTicket{value: 1.25 ether}(ticketA);

        // L'evento 2 viene annullato: Anna si fa rimborsare B
        ticket.cancelEvent(event2);
        vm.prank(anna);
        ticket.refundTicket(ticketB);

        assertEq(ticket.pendingWithdrawals(anna), 1.25 ether + PRICE);
    }

    // ------------------------------------------------------------- incassi

    function testClaimRevenue() public {
        uint256 eventId = _newEvent();
        _buy(anna, eventId);
        _buy(bob, eventId);

        vm.warp(eventDate + 1);
        ticket.claimRevenue(eventId);
        assertEq(ticket.pendingWithdrawals(address(this)), 2 * PRICE);

        uint256 before = address(this).balance;
        ticket.withdraw();
        assertEq(address(this).balance, before + 2 * PRICE);
    }

    function testClaimRevenueCancelledReverts() public {
        uint256 eventId = _newEvent();
        _buy(anna, eventId);
        ticket.cancelEvent(eventId);
        vm.warp(eventDate + 1);

        vm.expectRevert("Event cancelled");
        ticket.claimRevenue(eventId);
    }
}