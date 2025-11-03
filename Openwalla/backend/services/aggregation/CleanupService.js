class CleanupService {
  constructor(db) {
    this.db = db;
  }

  async cleanupOldData() {
    const cleanupQueries = [
      // Keep hourly data for 24 hours
      `DELETE FROM application_usage 
       WHERE timeperiod < datetime('now', '-24 hours')
       AND timeperiod >= datetime('now', '-30 days')`,
      
      // Keep daily data for 30 days
      `DELETE FROM application_usage 
       WHERE timeperiod < datetime('now', '-30 days')
       AND timeperiod >= datetime('now', '-1 year')`,
       
      // Keep monthly data for 1 year
      `DELETE FROM application_usage 
       WHERE timeperiod < datetime('now', '-1 year')`
    ];

    return new Promise((resolve, reject) => {
      this.db.serialize(() => {
        cleanupQueries.forEach(query => {
          this.db.run(query, [], (err) => {
            if (err) {
              console.error('Error during cleanup:', err);
            }
          });
        });
        resolve();
      });
    });
  }
}

module.exports = CleanupService;
