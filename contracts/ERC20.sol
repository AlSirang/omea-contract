// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BUSD is ERC20 {
    constructor() ERC20("TEST_BUSD", "TBUSD") {
        _mint(_msgSender(), 3000 ether);
    }
}
