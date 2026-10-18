// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract FairTicket is ERC721, AccessControl, ReentrancyGuard {
    bytes32 public constant ORGANIZER_ROLE = keccak256("ORGANIZER_ROLE");
    bytes32 public constant PROMOTER_ROLE = keccak256("PROMOTER_ROLE");
    bytes32 public constant USER_ROLE = keccak256("USER_ROLE");

    uint256 private constant BPS = 10_000;

    uint256 public constant MAX_MARKUP_BPS = 10_000;

    // Commissione dell'organizzatore sull'extraprofitto di una rivendita
    uint256 public constant COMMISSION_PERCENT = 5;
    // Commissione del promoter sul prezzo dei biglietti comprati dai suoi invitati
    uint256 public constant PROMOTER_COMMISSION_PERCENT = 2;
    uint256 public constant MAX_TICKETS = 5;

    struct DigitalEvent {
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
        uint256 lastPaid;
        bool used;
    }

    mapping(uint256 => DigitalEvent) public events;
    mapping(uint256 => Ticket) public tickets;
    mapping(uint256 => address) public eventOrganizer;
    mapping(uint256 => uint256) public resellTickets;
    mapping(address => uint256) public pendingWithdrawals;
    mapping(uint256 => bool) public revenueClaimed;
    mapping(address => address) public invitedBy;
    mapping(address => uint256) public maxTickets;
    // evento => totale delle commissioni maturate dai promoter (da togliere all'incasso dell'organizzatore)
    mapping(uint256 => uint256) public eventPromoterFees;
    // evento => promoter => commissione maturata e non ancora incassata
    mapping(uint256 => mapping(address => uint256)) public promoterEarned;

    uint256 private _nextEventId = 1;
    uint256 private _nextTicketId = 1;

    bool private _authorizedTransfer;

    event UserInvited(address indexed user, address indexed inviter);
    event EventCreated(
        uint256 indexed eventId, string name, uint64 date, uint256 price, uint32 maxSeats, address organizer
    );
    event EventCancelled(uint256 indexed eventId);
    event TicketPurchased(uint256 indexed eventId, uint256 indexed ticketId, address indexed buyer);
    event PromoterCommissionAccrued(
        uint256 indexed eventId, address indexed promoter, address indexed buyer, uint256 amount
    );
    event PromoterCommissionClaimed(uint256 indexed eventId, address indexed promoter, uint256 amount);
    event AttendanceConfirmed(uint256 indexed ticketId, uint256 indexed eventId, address indexed holder);
    event TicketTransfered(uint256 indexed ticketId, address indexed oldHolder, address indexed newHolder);
    event ResellList(uint256 indexed eventId, uint256 indexed ticketId, uint256 indexed price, address holder);
    event ResellTicketSold(
        uint256 indexed eventId,
        uint256 indexed ticketId,
        uint256 price,
        uint256 commission,
        address oldHolder,
        address indexed newHolder
    );
    event DeleteResellList(uint256 indexed ticketId, address holder);
    event TicketRefund(uint256 indexed ticketId, address indexed holder);
    event RevenueClaimed(uint256 indexed eventId, address indexed organizer, uint256 amount);
    event Withdrawal(address indexed account, uint256 amount);

    constructor() ERC721("FairTicket", "FRT") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ORGANIZER_ROLE, msg.sender);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    // Solo i promoter invitano, e solo utenti semplici: chi ha gia un ruolo (organizzatore,
    // promoter, admin) non si invita. L'invitato puo comprare come tutti gli altri, ma sui
    // suoi acquisti il promoter che l'ha invitato matura una commissione.
    function inviteUser(address user) external onlyRole(PROMOTER_ROLE) {
        require(user != address(0) && user != msg.sender, "Address not valid");
        require(
            !hasRole(ORGANIZER_ROLE, user) && !hasRole(PROMOTER_ROLE, user) && !hasRole(DEFAULT_ADMIN_ROLE, user),
            "Cannot invite a role holder"
        );
        require(!hasRole(USER_ROLE, user), "User already invited");

        _grantRole(USER_ROLE, user);
        invitedBy[user] = msg.sender;

        emit UserInvited(user, msg.sender);
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

        events[eventId] =
            DigitalEvent({name: name, date: date, price: price, maxSeats: maxSeats, sold: 0, cancelled: false});

        eventOrganizer[eventId] = msg.sender;

        emit EventCreated(eventId, name, date, price, maxSeats, msg.sender);
    }

    function cancelEvent(uint256 eventId) external onlyRole(ORGANIZER_ROLE) {
        DigitalEvent storage ev = events[eventId];

        require(ev.date != 0, "Evento inesistente");
        require(!ev.cancelled, "Evento cancellato");
        require(ev.date > block.timestamp, "Evento passato");
        require(msg.sender == eventOrganizer[eventId], "Non organizzatore dell evento");

        ev.cancelled = true;

        emit EventCancelled(eventId);
    }

    function confirmAttendance(uint256 ticketId) external {
        require(ownerOf(ticketId) == msg.sender, "You are not the owner");

        Ticket storage t = tickets[ticketId];
        DigitalEvent storage ev = events[t.eventId];

        require(!t.used, "Attendance already confirmed");
        require(!ev.cancelled, "Evento annullato");
        require(block.timestamp < ev.date, "Evento iniziato");

        t.used = true;
        delete resellTickets[ticketId];

        emit AttendanceConfirmed(ticketId, t.eventId, msg.sender);
    }

    function buyTicket(uint256 eventId) external payable nonReentrant returns (uint256 ticketId) {
        DigitalEvent storage ev = events[eventId];

        require(ev.date != 0, "Evento inesistente");
        require(!ev.cancelled, "Evento annullato");
        require(block.timestamp < ev.date, "Evento iniziato");
        require(ev.sold < ev.maxSeats, "Sold out");
        require(msg.value == ev.price, "Prezzo errato");
        require(maxTickets[msg.sender] < MAX_TICKETS, "You already purchased 5 tickets");

        ev.sold++;

        ticketId = _nextTicketId++;
        tickets[ticketId] = Ticket({eventId: eventId, pricePaid: msg.value, lastPaid: msg.value, used: false});
        maxTickets[msg.sender]++;

        // Se l'acquirente e stato invitato da un promoter (che ha ancora il ruolo), il promoter
        // matura il 2% del prezzo. I soldi restano nel contratto fino alla fine dell'evento: se
        // l'evento viene annullato servono per rimborsare il prezzo intero.
        address promoter = invitedBy[msg.sender];
        if (promoter != address(0) && hasRole(PROMOTER_ROLE, promoter)) {
            uint256 fee = (ev.price * PROMOTER_COMMISSION_PERCENT) / 100;
            promoterEarned[eventId][promoter] += fee;
            eventPromoterFees[eventId] += fee;

            emit PromoterCommissionAccrued(eventId, promoter, msg.sender, fee);
        }

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
        Ticket storage tick = tickets[ticketId];
        DigitalEvent storage ev = events[tick.eventId];

        if (ev.maxSeats == 0) return 0;

        uint256 markupBps = (MAX_MARKUP_BPS * ev.sold) / ev.maxSeats;

        return (tick.pricePaid * (BPS + markupBps)) / BPS;
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
        uint256 price = resellTickets[ticketId];

        require(price != 0, "Ticket not for sale");
        require(msg.sender != seller, "You cannot buy this ticket");
        require(msg.value == price, "Value not correct");

        (, Ticket storage tick) = _transferableTicket(ticketId);

        uint256 commission = 0;
        if (price > tick.lastPaid) {
            commission = ((price - tick.lastPaid) * COMMISSION_PERCENT) / 100;
        }

        tick.lastPaid = price;
        pendingWithdrawals[seller] += price - commission;
        pendingWithdrawals[eventOrganizer[tick.eventId]] += commission;

        _authorizedTransfer = true;
        _transfer(seller, msg.sender, ticketId);
        _authorizedTransfer = false;

        emit ResellTicketSold(tick.eventId, ticketId, price, commission, seller, msg.sender);
    }

    function refundTicket(uint256 ticketId) external {
        Ticket storage tick = tickets[ticketId];

        require(ownerOf(ticketId) == msg.sender, "You are not the owner");
        require(events[tick.eventId].cancelled, "The event is not cancelled");

        pendingWithdrawals[msg.sender] += tick.pricePaid;

        _burn(ticketId);

        emit TicketRefund(ticketId, msg.sender);
    }

    // All'organizzatore va il ricavato dei biglietti meno le commissioni dei promoter
    function claimRevenue(uint256 eventId) external {
        DigitalEvent storage ev = events[eventId];

        require(ev.date != 0, "Event not existing");
        require(msg.sender == eventOrganizer[eventId], "You are not the Organizer for this event");
        require(!ev.cancelled, "Event cancelled");
        require(block.timestamp > ev.date, "Event not ended yet");
        require(!revenueClaimed[eventId], "Revenue already claimed");

        revenueClaimed[eventId] = true;

        uint256 revenue = ev.price * ev.sold - eventPromoterFees[eventId];
        pendingWithdrawals[msg.sender] += revenue;

        emit RevenueClaimed(eventId, msg.sender, revenue);
    }

    // Il promoter incassa la sua commissione solo a evento finito e non annullato
    function claimPromoterCommission(uint256 eventId) external {
        DigitalEvent storage ev = events[eventId];

        require(ev.date != 0, "Event not existing");
        require(!ev.cancelled, "Event cancelled");
        require(block.timestamp > ev.date, "Event not ended yet");

        uint256 amount = promoterEarned[eventId][msg.sender];
        require(amount > 0, "No commission to claim");

        promoterEarned[eventId][msg.sender] = 0;
        pendingWithdrawals[msg.sender] += amount;

        emit PromoterCommissionClaimed(eventId, msg.sender, amount);
    }

    function withdraw() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "No amount to withdraw");

        pendingWithdrawals[msg.sender] = 0;

        emit Withdrawal(msg.sender, amount);

        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "Invio fallito");
    }

    function _transferableTicket(uint256 ticketId)
        internal
        view
        returns (DigitalEvent storage ev, Ticket storage tick)
    {
        tick = tickets[ticketId];
        ev = events[tick.eventId];

        require(!tick.used, "Ticket already used");
        require(!ev.cancelled, "Event cancelled");
        require(block.timestamp < ev.date, "Event already began");
    }

    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
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