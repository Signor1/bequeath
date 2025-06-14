//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IPUSHCommInterface} from "../../src/interface/IPushNotification.sol";

contract MockPushNotification is IPUSHCommInterface {
    event NotificationSent(address indexed channel, address indexed recipient, bytes identity);

    function sendNotification(address _channel, address _recipient, bytes calldata _identity) external {
        emit NotificationSent(_channel, _recipient, _identity);
    }
}
