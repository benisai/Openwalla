export interface Flow {
  timeinsert: string;
  hostname: string;
  local_ip: string;
  local_mac: string;
  fqdn: string;
  dest_ip: string;
  dest_port: number;
  dest_type: string;
  detected_protocol_name: string;
  detected_app_name: string;
  interface: string;
  internal: number;
}

export interface FlowDetailsData {
  device?: {
    name: string;
    ipAddress: string;
    port: string;
    macAddress: string;
    vendor: string;
  };
  destination?: {
    name: string;
    ipAddress: string;
    port: string;
    region: string;
    protocol?: string;
  };
  details?: {
    timestamp: string;
    direction: string;
    outboundInterface: string;
    flowCount: number;
    duration: string;
    downloaded: string;
    uploaded: string;
  };
}