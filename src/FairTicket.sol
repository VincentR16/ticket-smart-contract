pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";


contract FairTicket is ERC721, AccessControl, ReentrancyGuard {

    bytes32 public constant ORGANIZER_ROLE = keccak256("ORGANIZER_ROLE");
    bytes32 public constant STEWARD_ROLE = keccak256("STEWARD_ROLE");


    uint256 public constant MAX_MARKUP_PERCENT = 25;

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
    mapping(uint256 => address) public eventOrganizer;
    mapping(uint256 => uint256) public resellTickets;

    uint256 private _nextEventId = 1;
    uint256 private _nextTicketId = 1;

    event EventCreated(uint256 indexed eventId, string name, uint64 date, uint256 price, uint32 maxSeats, address eventOrganizer);
    event EventCancelled(uint256 indexed eventId);
    event TicketPurchased(uint256 indexed eventId, uint256 indexed ticketId, address indexed buyer);
    event TicketUsed(uint256 indexed ticketId, uint256 indexed eventId, address indexed holder);
    event TicketTransfered(uint256 indexed ticketId, address indexed oldHolder,  address indexed newHolder);
    event ResellList(uint256 indexed eventId, uint256 indexed ticketId, uint256 indexed price, address holder);





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

        eventOrganizer[eventId] = msg.sender;

        emit EventCreated(eventId, name, date, price, maxSeats, msg.sender);
    }

    function cancelEvent(uint256 eventId) external onlyRole(ORGANIZER_ROLE){
        SportEvent storage ev = events[eventId];

        require(ev.date != 0, "Event inesistente");
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

    function buyTicket(uint256 eventId) external payable nonReentrant returns (uint256 ticketId)
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

    function transferTicket(uint256 ticketId, address to) external nonReentrant{

        require(ownerOf(ticketId) == msg.sender, "Owner of the ticket required");
        require(to != address(0) && to != msg.sender, "Address not valid");

        _transferableTicket(ticketId);

        _transfer(msg.sender, to, ticketId);

        emit TicketTransfered(ticketId, msg.sender, to);
    }

    function maxResellPrice(uint256 ticketId) public view returns(uint256){
       return (tickets[ticketId].pricePaid * (100 + MAX_MARKUP_PERCENT)) / 100;}

    function addToResellTicket(uint256 ticketId, uint256 price) external{

        require(ownerOf(ticketId) == msg.sender, "You are not the owner");
        require(price > 0, "Prezzo non valido");
        require(price <= maxResellPrice(ticketId), "Price is too high");

        ( ,Ticket storage tick ) = _transferableTicket(ticketId);

        resellTickets[ticketId] = price;

  
        
        emit ResellList(tick.eventId, ticketId, price, msg.sender);
    }


 //todo controllare il controllo sul tempo della data, non ricordo come si fa la disugluaglianza con una data

    function _transferableTicket(uint256 ticketId) internal view returns(SportEvent storage ev, Ticket storage tick){

        tick = tickets[ticketId];
        ev = events[tick.eventId];

        require(!tick.used, "ticket already used!");
        require(!ev.cancelled, "Event cancelled");
        require(ev.date > block.timestamp, "Event alreay began");
    
    }

}