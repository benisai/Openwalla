import { DatabaseService } from '../src/services/DatabaseService';

async function seedDatabases() {
  // Notifications
  await DatabaseService.run('notifications', `
    INSERT INTO notifications (uuid, sev, type, msg, detect_time, action) VALUES
    ('1', 'high', 'security', 'Suspicious traffic detected', 1709668800, 'block'),
    ('2', 'medium', 'system', 'System update available', 1709665200, 'update'),
    ('3', 'low', 'network', 'High latency detected', 1709661600, 'monitor')
  `);

  // Devices
  await DatabaseService.run('openwrt', `
    INSERT INTO devices (uuid, name, type, mac, ip, netname, manufacturer, status, portscount) VALUES
    ('d1', 'Living Room TV', 'entertainment', '00:1A:2B:3C:4D:5E', '192.168.1.100', 'LAN', 'Samsung', 'active', 2),
    ('d2', 'iPhone 13', 'mobile', '00:1A:2B:3C:4D:5F', '192.168.1.101', 'LAN', 'Apple', 'active', 1),
    ('d3', 'Gaming PC', 'computer', '00:1A:2B:3C:4D:60', '192.168.1.102', 'LAN', 'Custom', 'active', 4)
  `);

  // Hourly WAN Usage
  await DatabaseService.run('hourlyWanUsage', `
    INSERT INTO hourlywanusage (uuid, interface, name, hour, download, upload) VALUES
    ('h1', 'eth0', 'WAN', 1, 25.5, 10.2),
    ('h2', 'eth0', 'WAN', 2, 30.1, 12.5),
    ('h3', 'eth0', 'WAN', 3, 28.7, 11.8)
  `);

  // Ping Stats
  await DatabaseService.run('pingStats', `
    INSERT INTO pingstats (uuid, ip, ms, max_latency, median_latency, packetloss, date, time) VALUES
    ('p1', '8.8.8.8', 15, 25.5, 18.2, 0.1, '2024-03-06', '10:00:00'),
    ('p2', '8.8.8.8', 18, 28.1, 20.5, 0.2, '2024-03-06', '10:01:00'),
    ('p3', '8.8.8.8', 12, 22.7, 15.8, 0.0, '2024-03-06', '10:02:00')
  `);

  // Flow data
  await DatabaseService.run('flows', `
    INSERT INTO flow (timeinsert, hostname, local_ip, local_mac, fqdn, dest_ip, dest_port, dest_type, detected_protocol_name, detected_app_name, vlan_id, interface, internal) VALUES
    ('2024-03-06 10:00:00', 'iphone-13', '192.168.1.101', '00:1A:2B:3C:4D:5F', 'netflix.com', '54.192.151.12', 443, 'streaming', 'HTTPS', 'Netflix', 1, 'eth0', 0),
    ('2024-03-06 10:01:00', 'gaming-pc', '192.168.1.102', '00:1A:2B:3C:4D:60', 'steam.com', '23.59.247.10', 443, 'gaming', 'HTTPS', 'Steam', 1, 'eth0', 0),
    ('2024-03-06 10:02:00', 'living-room-tv', '192.168.1.100', '00:1A:2B:3C:4D:5E', 'youtube.com', '142.250.190.78', 443, 'streaming', 'HTTPS', 'YouTube', 1, 'eth0', 0)
  `);

  console.log('Databases seeded successfully');
}

// Run the seeding
seedDatabases().catch(console.error);