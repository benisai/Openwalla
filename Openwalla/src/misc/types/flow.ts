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
  ndpi_risk_score: number;
  ndpi_risk_score_client: number;
  ndpi_risk_score_server: number;
  client_sni: string;
  category_application: number;
  category_domain: number;
  category_protocol: number;
  detected_application: number;
  detected_protocol: number;
  detection_guessed: number;
  dns_host_name: string;
  host_server_name: string;
  digest?: string;
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
    uploaded: string;
    downloaded: string;
    digest?: string;
  };
  categories?: {
    application: number;
    domain: number;
    protocol: number;
  };
  detection?: {
    application: number;
    applicationName: string;
    protocol: number;
    protocolName: string;
    guessed: boolean;
    hostnames: {
      dns: string;
      server: string;
    };
  };
}
