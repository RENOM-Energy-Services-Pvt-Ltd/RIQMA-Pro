/**
 * Firebase Cloud Functions for RIQMA Pro
 * 
 * Sends push notifications to Managers when Auditors perform specific actions.
 * Triggers on new entries in the 'activity_logs' collection.
 */

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

// Initialize Firebase Admin
initializeApp();

const db = getFirestore();
const messaging = getMessaging();

/**
 * Formats a Firestore Timestamp to readable time (e.g., '11:00 PM')
 * @param {Object} timestamp - Firestore Timestamp object
 * @returns {string} Formatted time string
 */
function formatTime(timestamp) {
  const options = {
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
    timeZone: "Asia/Kolkata", // Explicitly set to IST
  };

  if (!timestamp || !timestamp.toDate) {
    return new Date().toLocaleTimeString("en-IN", options);
  }

  const date = timestamp.toDate();
  return date.toLocaleTimeString("en-IN", options);
}

/**
 * Builds notification message based on action type
 * @param {Object} logData - Activity log document data
 * @returns {Object|null} Notification title and body, or null if not applicable
 */
function buildNotificationMessage(logData) {
  const { actionType, userName, metadata } = logData;
  const formattedTime = formatTime(logData.timestamp);

  // Always prefer the human-readable name; fall back to ID only if name is absent
  const turbineDisplayName = metadata?.turbineName || metadata?.turbineId || "Unknown Turbine";
  const siteDisplayName = metadata?.siteName || metadata?.siteId || "Unknown Site";

  let title = "";
  let body = "";

  switch (actionType) {
    case "AUDIT_START":
      title = "🔍 Audit Started";
      body = `${userName} has started audit for ${turbineDisplayName} (${siteDisplayName}) at ${formattedTime}`;
      break;

    case "AUDIT_SUBMIT":
      title = "✅ Audit Submitted";
      body = `${userName} has submitted audit for ${turbineDisplayName} (${siteDisplayName}) at ${formattedTime}`;
      break;

    case "AUDIT_PLAN_ADD":
      title = "📋 New Plan Added";
      body = `${userName} has added a new plan for ${siteDisplayName} at ${formattedTime}`;
      break;

    default:
      // Don't send notifications for other action types (LOGIN, LOGOUT, etc.)
      return null;
  }

  return { title, body };
}

/**
 * Cloud Function: sendAuditNotification
 * Triggers when a new document is created in 'activity_logs' collection.
 * Sends push notifications to all Managers.
 */
exports.sendAuditNotification = onDocumentCreated(
  "activity_logs/{logId}",
  async (event) => {
    const logData = event.data?.data();
    const logId = event.params.logId;

    if (!logData) {
      console.log("No log data found for", logId);
      return null;
    }

    console.log("Processing activity log:", logId, logData.actionType);

    // Build notification message
    const notification = buildNotificationMessage(logData);

    if (!notification) {
      console.log("Skipping notification for action type:", logData.actionType);
      return null;
    }

    try {
      const tokens = new Set(); // Use Set to avoid duplicate tokens

      // 1. Fetch all managers' FCM tokens
      const managersSnapshot = await db
        .collection("users")
        .where("role", "==", "manager")
        .get();

      managersSnapshot.forEach((doc) => {
        const userData = doc.data();
        if (userData.fcmToken) {
          tokens.add(userData.fcmToken);
        }
      });

      console.log(`Found ${managersSnapshot.size} manager(s)`);

      // 2. Fetch the auditor's FCM token (who performed the action)
      if (logData.userId) {
        const auditorDoc = await db.collection("users").doc(logData.userId).get();
        if (auditorDoc.exists) {
          const auditorData = auditorDoc.data();
          if (auditorData.fcmToken) {
            tokens.add(auditorData.fcmToken);
            console.log("Added auditor's token for self-notification");
          }
        }
      }

      // Convert Set to Array
      const tokenArray = Array.from(tokens);

      if (tokenArray.length === 0) {
        console.log("No FCM tokens found for managers or auditor");
        return null;
      }

      console.log(`Sending notification to ${tokenArray.length} recipient(s) (Managers + Auditor)`);

      // Build the multicast message
      const message = {
        notification: {
          title: notification.title,
          body: notification.body,
        },
        data: {
          click_action: "FLUTTER_NOTIFICATION_CLICK",
          logId: logId,
          actionType: logData.actionType,
          auditId: logData.metadata?.auditId || "",
          siteId: logData.metadata?.siteId || "",
          siteName: logData.metadata?.siteName || "",
          turbineId: logData.metadata?.turbineId || "",
          userId: logData.userId || "",
          userName: logData.userName || "",
        },
        tokens: tokenArray,
        android: {
          priority: "high",
          notification: {
            sound: "default",
            channelId: "high_importance_channel",
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: 1,
            },
          },
        },
      };

      // Send multicast notification
      const response = await messaging.sendEachForMulticast(message);

      console.log(
        `Notifications sent: ${response.successCount} successful, ${response.failureCount} failed`
      );

      // Log failures for debugging
      if (response.failureCount > 0) {
        response.responses.forEach((resp, idx) => {
          if (!resp.success) {
            console.log(`Failed to send to token ${idx}:`, resp.error?.message);
          }
        });
      }

      return { success: true, sent: response.successCount };

    } catch (error) {
      console.error("Error sending notifications:", error);
      return { success: false, error: error.message };
    }
  }
);
