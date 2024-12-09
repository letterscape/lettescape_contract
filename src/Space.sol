// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./LSNFT.sol";

contract Space {
  
  address public lsnft;

  // author => ids
  mapping(address => string[]) private allIdMap;

  mapping(address => string[]) private showedIdMap;

  // id => content
  mapping(string => Content) private contents;

  mapping(address => mapping(string => bool)) private favourites;

  uint256[50] _placeholder1;

  struct Content {
    bool isShowed;
    bool isDeleted;
    address author;
    uint256 label;
    uint256 favouriteNum; // number of favourite
    string id;
    string title;
    string resource; // uri or cid etc.
  }

  modifier isAuthor(string memory id) {
    Content memory c = contentOf(id);
    if (msg.sender != c.author) {
      revert RequiredAuthorPerm(msg.sender, block.timestamp);
    }
    _;
  }

  event Create(address indexed author, string indexed id, uint256 indexed label, uint256 createTime);

  event Modify(address indexed author, string indexed id, uint256 indexed label, string modifiedFieldName, uint256 modifyTIme);

  error RequiredAuthorPerm(address sender, uint256 timestamp);

  constructor(address _lsnft) {
    lsnft = _lsnft;
  }

  function create(string memory _id, string memory _title, string memory _resource, string memory originURI) public {
    address author = msg.sender;
    Content memory content = Content({
      isShowed: false,
      isDeleted: false,
      author: author,
      label: 0,
      favouriteNum: 0,
      id: _id,
      title: _title,
      resource: _resource
    });
    string[] storage ids = allIdMap[author];
    ids.push(_id);
    contents[_id] = content;

    // creators bind their content to their address
    LSNFT(lsnft).bind(originURI, author);

    emit Create(author, _id, content.label, block.timestamp);
  }

  function setShowStatus(string memory _id, bool _isShowed) public isAuthor(_id) {
    address author = msg.sender;
    string[] storage ids = showedIdMap[author];
    Content memory c = contentOf(_id);
    if (_isShowed) {
      ids.push(_id);
      c.isShowed = true;
    } else {
      for (uint i = 0; i < ids.length; i++) {
        if (keccak256(abi.encodePacked(ids[i])) == keccak256(abi.encodePacked(_id))) {
          ids[i] = ids[ids.length - 1];
          ids.pop();
          break;
        }
      }
      c.isShowed = false;
    }

    emit Modify(author, _id, c.label, "isShowed", block.timestamp);
  }

  function deleteContent(string memory _id) public isAuthor(_id) {
    Content storage c = contents[_id];
    c.isDeleted = true;
  }

  function modifyTitle(string memory _id, string memory _title) public isAuthor(_id) {
    Content memory c = contentOf(_id);
    c.title = _title;

    emit Modify(c.author, _id, c.label, "title", block.timestamp);
  }

  function favour(string memory _id) public {
    if (isfavourite(_id)) {
      return;
    }
    favourites[msg.sender][_id] = true;
    Content memory c = contentOf(_id);
    c.favouriteNum += 1;

    emit Modify(msg.sender, _id, c.label, "favouriteNum", block.timestamp);
  }

  function contentOf(string memory _id) public view returns (Content memory) {
    return contents[_id];
  }

  function totalOf() public view returns (uint256) {
    address author = msg.sender;
    string[] memory ids = showedIdMap[author];
    return ids.length;
  }

  function allOf() public view returns (string[] memory) {
    return allIdMap[msg.sender];
  }

  function showedOf() public view returns (string[] memory) {
    return showedIdMap[msg.sender];
  }

  function isfavourite(string memory _id) public view returns (bool) {
    return favourites[msg.sender][_id];
  }
}