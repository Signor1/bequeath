//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @author  push-notification
 * @title   PUSH Comm Contract Interface
 * @dev     This interface defines the functions for sending push notifications to users.
 * @notice  The oracle allows sending notifications with a title and body to a specified recipient address.
 */
interface IPUSHCommInterface {
    /**
     * @notice Sends a notification to a recipient address.
     * @param _channel The address of the channel sending the notification.
     * @param _recipient The address of the recipient who will receive the notification.
     * @param _identity The identity of the recipient, typically a hash or identifier.
     */
    function sendNotification(address _channel, address _recipient, bytes calldata _identity) external;
}
