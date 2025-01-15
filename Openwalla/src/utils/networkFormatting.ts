export const formatBytes = (bytes: number): string => {
  if (bytes === 0) return '0 B';

  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));

  return `${parseFloat((bytes / Math.pow(k, i)).toFixed(2))} ${sizes[i]}`;
};

export function formatNetworkSpeed(speedInKbps: number): string {
  // Convert to bits first (1 kilobit = 1000 bits)
  const bits = speedInKbps * 1000;
  
  // Format for Gigabits
  if (bits >= 1000000000) {
    return `${(bits / 1000000000).toFixed(2)} Gbps`;
  }
  
  // Format for Megabits
  if (bits >= 1000000) {
    return `${(bits / 1000000).toFixed(2)} Mbps`;
  }
  
  // Format for Kilobits
  if (bits >= 1000) {
    return `${(bits / 1000).toFixed(2)} Kbps`;
  }
  
  // Format for bits
  return `${bits.toFixed(2)} bps`;
}