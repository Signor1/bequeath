//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @author  push-notification (Proposed Push Notification)
 * @title   Proposed Push Notification Interface
 * @dev     This interface defines the functions for sending push notifications to users.
 * @notice  The oracle allows sending notifications with a title and body to a specified recipient address.
 */
interface IPushNotification {
    /**
     * @notice Sends a push notification to a specified recipient.
     * @param recipient The address of the recipient who will receive the notification.
     * @param title The title of the notification.
     * @param body The body content of the notification.
     */
    function sendNotification(
        address recipient,
        string calldata title,
        string calldata body
    ) external;
}
