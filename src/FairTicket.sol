pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";


contract FairTicket is ERC721, AccessControl, ReentrancyGuard {

    struct SportEvent{
        string name;
        uint64 date;
        uint256 price;
        uint32 maxSeats;
        uint32 sold;
        bool cancelled;
    }

    struct Ticket{
        uint256 eventId;
        uint256 pricePaid;
        bool used;
    }

    mapping(uint256 => SportEvent) public events;
    mapping(uint256 => Ticket) public tickets;

    uint256 private _nextEventId = 1;
    uint256 private _nextTicketId = 1;

    event EventCreated(uint256 indexed eventId, string name, uint64 date, uint256 price, uint32 maxSeats);
    event TicketPurchased(uint256 indexed eventId, uint256 indexed ticketId, address indexed buyer);
    event TicketUsed(uint256 indexed ticketId, uint256 indexed eventId, address indexed holder);

    bytes32 public constant ORGANIZER_ROLE = keccak256("ORGANIZER_ROLE");
    bytes32 public constant STEWARD_ROLE = keccak256("STEWARD_ROLE");

    constructor() ERC721("FairRicket", "FRT"){
     _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(ORGANIZER_ROLE, msg.sender);
    }


    function supportsInterface(bytes4 interfaceId)
        public view override(ERC721, AccessControl) returns (bool)
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

        emit EventCreated(eventId, name, date, price, maxSeats);
    }


    function checkIn(uint256 ticketId) external onlyRole(STEWARD_ROLE) {
        address holder = ownerOf(ticketId); 

        Ticket storage t = tickets[ticketId];

        require(!t.used, "Biglietto gia usato");
        require(!events[t.eventId].cancelled, "Evento annullato");

        t.used = true;

        emit TicketUsed(ticketId, t.eventId, holder);
    }

    function buyTicket(uint256 eventId)
    external
    payable
    nonReentrant
    returns (uint256 ticketId)
{
    SportEvent storage ev = events[eventId];

    require(ev.date != 0, "Evento inesistente");
    require(!ev.cancelled, "Evento annullato");
    require(block.timestamp < ev.date, "Evento iniziato");
    require(ev.sold < ev.maxSeats, "Sold out");
    require(msg.value == ev.price, "Prezzo errato");

    ev.sold++;

    ticketId = _nextTicketId++;
    tickets[ticketId] = Ticket({
        eventId: eventId,
        pricePaid: msg.value,
        used: false
    });

    emit TicketPurchased(eventId, ticketId, msg.sender);
    
    _safeMint(msg.sender, ticketId);

}

}