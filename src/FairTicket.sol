// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract FairTicket is ERC721, AccessControl, ReentrancyGuard {
    bytes32 public constant ORGANIZER_ROLE = keccak256("ORGANIZER_ROLE");
    bytes32 public constant STEWARD_ROLE = keccak256("STEWARD_ROLE");

    uint256 public constant MAX_MARKUP_PERCENT = 25;

    struct SportEvent {
        string name;
        uint64 date;
        uint256 price;
        uint32 maxSeats;
        uint32 sold;
        bool cancelled;
    }

    struct Ticket {
        uint256 eventId;
        uint256 pricePaid;
        bool used;
    }

    mapping(uint256 => SportEvent) public events;
    mapping(uint256 => Ticket) public tickets;
    mapping(uint256 => address) public eventOrganizer;
    mapping(uint256 => uint256) public resellTickets;
    mapping(address => uint256) public pendingWithdrawals;
    mapping(uint256 => bool) public revenueClaimed;

    uint256 private _nextEventId = 1;
    uint256 private _nextTicketId = 1;

    bool private _authorizedTransfer;

    event EventCreated(uint256 indexed eventId, string name, uint64 date, uint256 price, uint32 maxSeats, address organizer);
    event EventCancelled(uint256 indexed eventId);
    event TicketPurchased(uint256 indexed eventId, uint256 indexed ticketId, address indexed buyer);
    event TicketUsed(uint256 indexed ticketId, uint256 indexed eventId, address indexed holder);
    event TicketTransfered(uint256 indexed ticketId, address indexed oldHolder, address indexed newHolder);
    event ResellList(uint256 indexed eventId, uint256 indexed ticketId, uint256 indexed price, address holder);
    event ResellTicketSold(uint256 indexed eventId, uint256 indexed ticketId, uint256 price, address oldHolder, address indexed newHolder);
    event DeleteResellList(uint256 indexed ticketId, address holder);
    event TicketRefund(uint256 indexed ticketId, address indexed holder);
    event RevenueClaimed(uint256 indexed eventId, address indexed organizer, uint256 amount);
    event Withdrawal(address indexed account, uint256 amount);

    constructor() ERC721("FairTicket", "FRT") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ORGANIZER_ROLE, msg.sender);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function createEvent(string calldata name, uint64 date, uint256 price, uint32 maxSeats)
        external
        onlyRole(ORGANIZER_ROLE)
        returns (uint256 eventId)
    {
        require(date > block.timestamp, "Data nel passato");
        require(price > 0, "Prezzo non valido");
        require(maxSeats > 0, "Posti non validi");

        eventId = _nextEventId++;

        events[eventId] = SportEvent({
            name: name,
            date: date,
            price: price,
            maxSeats: maxSeats,
            sold: 0,
            cancelled: false
        });

        eventOrganizer[eventId] = msg.sender;

        emit EventCreated(eventId, name, date, price, maxSeats, msg.sender);
    }

    function cancelEvent(uint256 eventId) external onlyRole(ORGANIZER_ROLE) {
        SportEvent storage ev = events[eventId];

        require(ev.date != 0, "Evento inesistente");
        require(!ev.cancelled, "Evento cancellato");
        require(ev.date > block.timestamp, "Evento passato");
        require(msg.sender == eventOrganizer[eventId], "Non organizzatore dell evento");

        ev.cancelled = true;

        emit EventCancelled(eventId);
    }

    function checkIn(uint256 ticketId) external onlyRole(STEWARD_ROLE) {
        address holder = ownerOf(ticketId);

        Ticket storage t = tickets[ticketId];

        require(!t.used, "Biglietto gia usato");
        require(!events[t.eventId].cancelled, "Evento annullato");

        t.used = true;

        emit TicketUsed(ticketId, t.eventId, holder);
    }

    function buyTicket(uint256 eventId) external payable nonReentrant returns (uint256 ticketId) {
        SportEvent storage ev = events[eventId];

        require(ev.date != 0, "Evento inesistente");
        require(!ev.cancelled, "Evento annullato");
        require(block.timestamp < ev.date, "Evento iniziato");
        require(ev.sold < ev.maxSeats, "Sold out");
        require(msg.value == ev.price, "Prezzo errato");

        ev.sold++;

        ticketId = _nextTicketId++;
        tickets[ticketId] = Ticket({eventId: eventId, pricePaid: msg.value, used: false});

        emit TicketPurchased(eventId, ticketId, msg.sender);

        _safeMint(msg.sender, ticketId);
    }

    function transferTicket(uint256 ticketId, address to) external nonReentrant {
        require(ownerOf(ticketId) == msg.sender, "Owner of the ticket required");
        require(to != address(0) && to != msg.sender, "Address not valid");

        _transferableTicket(ticketId);

        _authorizedTransfer = true;
        _transfer(msg.sender, to, ticketId);
        _authorizedTransfer = false;

        emit TicketTransfered(ticketId, msg.sender, to);
    }

    function maxResellPrice(uint256 ticketId) public view returns (uint256) {
        return (tickets[ticketId].pricePaid * (100 + MAX_MARKUP_PERCENT)) / 100;
    }

    function addToResellTicket(uint256 ticketId, uint256 price) external {
        require(ownerOf(ticketId) == msg.sender, "You are not the owner");
        require(price > 0, "Prezzo non valido");
        require(price <= maxResellPrice(ticketId), "Price is too high");

        (, Ticket storage tick) = _transferableTicket(ticketId);

        resellTickets[ticketId] = price;

        emit ResellList(tick.eventId, ticketId, price, msg.sender);
    }

    function deleteResellTicket(uint256 ticketId) external {
        require(ownerOf(ticketId) == msg.sender, "You are not the owner");
        require(resellTickets[ticketId] != 0, "Ticket not for sale");

        delete resellTickets[ticketId];

        emit DeleteResellList(ticketId, msg.sender);
    }

    function buyResellTicket(uint256 ticketId) external payable nonReentrant {
        address seller = ownerOf(ticketId);

        require(resellTickets[ticketId] != 0, "Ticket not for sale");
        require(msg.sender != seller, "You cannot buy this ticket");
        require(msg.value == resellTickets[ticketId], "Value not correct");

        (, Ticket storage tick) = _transferableTicket(ticketId);

        pendingWithdrawals[seller] += msg.value;

        _authorizedTransfer = true;
        _transfer(seller, msg.sender, ticketId);
        _authorizedTransfer = false;

        emit ResellTicketSold(tick.eventId, ticketId, msg.value, seller, msg.sender);
    }

    function refundTicket(uint256 ticketId) external {
        Ticket storage tick = tickets[ticketId];

        require(ownerOf(ticketId) == msg.sender, "You are not the owner");
        require(events[tick.eventId].cancelled, "The event is not cancelled");

        pendingWithdrawals[msg.sender] += tick.pricePaid;

        _burn(ticketId);

        emit TicketRefund(ticketId, msg.sender);
    }

    function claimRevenue(uint256 eventId) external {
        SportEvent storage ev = events[eventId];

        require(ev.date != 0, "Event not existing");
        require(msg.sender == eventOrganizer[eventId], "You are not the Organizer for this event");
        require(!ev.cancelled, "Event cancelled");
        require(block.timestamp > ev.date, "Event not ended yet");
        require(!revenueClaimed[eventId], "Revenue already claimed");

        revenueClaimed[eventId] = true;

        uint256 revenue = ev.price * ev.sold;
        pendingWithdrawals[msg.sender] += revenue;

        emit RevenueClaimed(eventId, msg.sender, revenue);
    }

    function withdraw() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "No amount to withdraw");

        pendingWithdrawals[msg.sender] = 0;

        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "Invio fallito");

        emit Withdrawal(msg.sender, amount);
    }

    function _transferableTicket(uint256 ticketId)
        internal
        view
        returns (SportEvent storage ev, Ticket storage tick)
    {
        tick = tickets[ticketId];
        ev = events[tick.eventId];

        require(!tick.used, "Ticket already used");
        require(!ev.cancelled, "Event cancelled");
        require(block.timestamp < ev.date, "Event already began");
    }

    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        returns (address)
    {
        address from = _ownerOf(tokenId);

        if (from != address(0)) {
            delete resellTickets[tokenId];

            if (to != address(0)) {
                require(_authorizedTransfer, "Direct transfer not allowed");
                require(!tickets[tokenId].used, "Ticket already used");
            }
        }

        return super._update(to, tokenId, auth);
    }
}