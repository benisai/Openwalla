export interface Device {
  mac: string;
  ip: string;
  hostname: string;
  dl_speed: number;
  ul_speed: number;
  total_download: number;
  total_upload: number;
  last_seen: number;
}