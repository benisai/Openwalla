const axios = require('axios');
const { databases } = require('../database');

class AdblockService {
  static async fetchAndParseAdblockData() {
    try {
      const response = await axios.get('http://10.0.3.1/adblock.txt');
      const data = response.data;

      // Parse the data
      const lines = data.split('\n');
      let section = '';
      const parsedData = {
        topClients: [],
        topDomains: [],
        blockedDomains: [],
        dnsQueries: []
      };

      for (const line of lines) {
        if (line.includes('Top 10 Clients')) {
          section = 'clients';
          continue;
        } else if (line.includes('Top 10 Domains')) {
          section = 'domains';
          continue;
        } else if (line.includes('Top 10 Blocked Domains')) {
          section = 'blocked';
          continue;
        } else if (line.includes('Latest DNS Queries')) {
          section = 'queries';
          continue;
        }

        // Skip empty lines and headers
        if (!line.trim() || line.startsWith('Start') || line.startsWith('End') || line.startsWith('Total')) {
          continue;
        }

        switch (section) {
          case 'clients':
            const clientMatch = line.trim().match(/(\d+)\s+(\d+\.\d+\.\d+\.\d+)/);
            if (clientMatch) {
              parsedData.topClients.push({
                count: parseInt(clientMatch[1]),
                ip: clientMatch[2]
              });
            }
            break;

          case 'domains':
            const domainMatch = line.trim().match(/(\d+)\s+(.+)/);
            if (domainMatch) {
              parsedData.topDomains.push({
                count: parseInt(domainMatch[1]),
                domain: domainMatch[2].trim()
              });
            }
            break;

          case 'blocked':
            const blockedMatch = line.trim().match(/(\d+)\s+(.+)/);
            if (blockedMatch) {
              parsedData.blockedDomains.push({
                count: parseInt(blockedMatch[1]),
                domain: blockedMatch[2].trim()
              });
            }
            break;

          case 'queries':
            const queryMatch = line.match(/(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})\s+(\d+\.\d+\.\d+\.\d+)\s+(\S+)\s+(\w+)/);
            if (queryMatch) {
              parsedData.dnsQueries.push({
                date: queryMatch[1],
                time: queryMatch[2],
                client: queryMatch[3],
                domain: queryMatch[4],
                answer: queryMatch[5]
              });
            }
            break;
        }
      }

      // Store the parsed data in the database
      await this.storeAdblockData(parsedData);
      return parsedData;
    } catch (error) {
      console.error('Error fetching or parsing adblock data:', error);
      throw error;
    }
  }

  static async storeAdblockData(data) {
    const db = databases.adblock;

    // Clear existing data
    await db.run('DELETE FROM adblock_top_clients');
    await db.run('DELETE FROM adblock_top_domains');
    await db.run('DELETE FROM adblock_blocked_domains');
    await db.run('DELETE FROM adblock_dns_queries');

    // Insert new data
    const statements = {
      clients: db.prepare('INSERT INTO adblock_top_clients (client_ip, query_count) VALUES (?, ?)'),
      domains: db.prepare('INSERT INTO adblock_top_domains (domain, query_count) VALUES (?, ?)'),
      blocked: db.prepare('INSERT INTO adblock_blocked_domains (domain, block_count) VALUES (?, ?)'),
      queries: db.prepare('INSERT INTO adblock_dns_queries (query_date, query_time, client_ip, domain, answer) VALUES (?, ?, ?, ?, ?)')
    };

    try {
      db.serialize(() => {
        db.run('BEGIN TRANSACTION');

        data.topClients.forEach(client => {
          statements.clients.run(client.ip, client.count);
        });

        data.topDomains.forEach(domain => {
          statements.domains.run(domain.domain, domain.count);
        });

        data.blockedDomains.forEach(domain => {
          statements.blocked.run(domain.domain, domain.count);
        });

        data.dnsQueries.forEach(query => {
          statements.queries.run(query.date, query.time, query.client, query.domain, query.answer);
        });

        db.run('COMMIT');
      });
    } catch (error) {
      console.error('Error storing adblock data:', error);
      db.run('ROLLBACK');
      throw error;
    } finally {
      Object.values(statements).forEach(stmt => stmt.finalize());
    }
  }
}

module.exports = AdblockService;