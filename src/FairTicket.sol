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
        uint256 pricepaid;
        bool used;
    }

    mapping(uint256 => SportEvent) public events;
    mapping(uint256 => Ticket) public tickets;

    uint256 private _nextEventId = 1;
    uint256 private _nextTicketId = 1;

    event EventCreated(uint256 indexed eventId, string name, uint64 date, uint256 price, uint32 maxSeats);
    event TicketPurchased(uint256 indexed eventId, uint256 indexed ticketId, address indexed buyer);

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

}