/**
 * Time utility functions for consistent timestamp handling across the application
 */

class TimeUtils {
  /**
   * Get current time as ISO string using local server time
   * This ensures correct time representation in the database
   * @returns {string} ISO 8601 formatted timestamp
   */
  static getLocalISOTime() {
    return new Date().toISOString();
  }

  /**
   * Get current time as Unix timestamp (seconds)
   * @returns {number} Unix timestamp in seconds
   */
  static getUnixTimestamp() {
    return Math.floor(Date.now() / 1000);
  }

  /**
   * Get current time as Unix timestamp (milliseconds)
   * @returns {number} Unix timestamp in milliseconds
   */
  static getUnixTimestampMs() {
    return Date.now();
  }
}

module.exports = TimeUtils;
