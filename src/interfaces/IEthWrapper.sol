// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;


interface IEthWrapper {

    function deposit() external payable;

    function withdraw(uint wad) external;

}