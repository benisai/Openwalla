const databases = require('./connections');
const { initializeConfigSchema } = require('./schemas/configSchema');
const { initializeNotificationSchema } = require('./schemas/notificationSchema');
const { initializeDeviceSchema } = require('./schemas/deviceSchema');
const { initializeFlowSchema } = require('./schemas/flowSchema');
const { initializeVnstatSchema } = require('./schemas/vnstatSchema');
const { initializeOuiVendorSchema } = require('./schemas/ouiVendorSchema');
const { initializePingStatsSchema } = require('./schemas/pingStatsSchema');
const { initializeAdblockSchema } = require('./schemas/adblockSchema');

async function initializeDatabases() {
  try {
    await Promise.all([
      initializeConfigSchema(),
      initializeNotificationSchema(),
      initializeDeviceSchema(),
      initializeFlowSchema(),
      initializeVnstatSchema(),
      initializeOuiVendorSchema(),
      initializePingStatsSchema(),
      initializeAdblockSchema()
    ]);
    console.log('All database tables initialized successfully');
  } catch (error) {
    console.error('Error initializing database tables:', error);
    throw error;
  }
}

module.exports = {
  databases,
  initializeDatabases
};