import React, { useEffect, useState } from "react";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { FlowDetailsData } from "@/misc/types/flow";
import { useQuery } from "@tanstack/react-query";
import { getFlowUsageByDigest } from "@/services/FlowService";
import { getConfig } from "@/services/ConfigService";
import { MapPin, ChevronDown, ChevronUp } from "lucide-react";

interface IpLookupData {
  country: string;
  latitude: string;
  longitude: string;
  continent: string;
  timezone: string;
  accuracyRadius: number;
  asn: number;
  asnOrganization: string;
  asnNetwork: string;
}

interface FlowDetailsProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  flowData: FlowDetailsData;
}

async function fetchDeviceHostname(mac: string | undefined) {
  if (!mac) return null;
  const response = await fetch(`/api/devices/${mac}`);
  if (!response.ok) {
    console.error('Failed to fetch device hostname');
    return null;
  }
  const data = await response.json();
  return data.hostname;
}

async function fetchVendor(mac: string | undefined) {
  if (!mac) return null;
  const response = await fetch(`/api/vendor/${mac}`);
  if (!response.ok) {
    console.error('Failed to fetch vendor');
    return null;
  }
  const data = await response.json();
  return data.vendor;
}

async function fetchIpLookup(ip: string, domain: string): Promise<IpLookupData | null> {
  try {
    const response = await fetch(`${domain}/${ip}`);
    if (!response.ok) {
      console.error('Failed to fetch IP lookup data');
      return null;
    }
    return await response.json();
  } catch (error) {
    console.error('Error fetching IP lookup:', error);
    return null;
  }
}

export function FlowDetailsDialog({ open, onOpenChange, flowData }: FlowDetailsProps) {
  const [showIpDetails, setShowIpDetails] = useState(false);
  
  const { data: hostname } = useQuery({
    queryKey: ['device-hostname', flowData.device?.macAddress],
    queryFn: () => fetchDeviceHostname(flowData.device?.macAddress),
    enabled: !!flowData.device?.macAddress,
  });

  const { data: vendor } = useQuery({
    queryKey: ['device-vendor', flowData.device?.macAddress],
    queryFn: () => fetchVendor(flowData.device?.macAddress),
    enabled: !!flowData.device?.macAddress,
  });

  const { data: config } = useQuery({
    queryKey: ['config'],
    queryFn: getConfig,
  });

  const { data: ipLookup, isLoading: isLoadingIp } = useQuery({
    queryKey: ['ip-lookup', flowData.destination?.ipAddress],
    queryFn: () => fetchIpLookup(flowData.destination?.ipAddress || '', config?.ip_lookup_domain || 'ip.benisai.com'),
    enabled: showIpDetails && !!flowData.destination?.ipAddress && !!config?.ip_lookup_domain,
  });
  
  const digestValue = flowData.details?.digest || '';
  
  useEffect(() => {
    if (open && digestValue) {
      console.log('Flow digest value in dialog component:', digestValue);
    }
  }, [digestValue, open]);

  const { data: flowUsage, isLoading: isLoadingUsage, isError: isErrorUsage } = useQuery({
    queryKey: ['flow-usage', digestValue],
    queryFn: () => getFlowUsageByDigest(digestValue),
    enabled: digestValue.length > 0,
    retry: 2, // Retry up to 2 times in case of network issues
    staleTime: 60000, // Cache for 1 minute
  });

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="bg-dashboard-card border-none max-w-md max-h-[90vh] overflow-hidden flex flex-col">
        <DialogHeader>
          <DialogTitle className="text-white">Flow Details</DialogTitle>
        </DialogHeader>

        <div className="mt-4 flex-1 overflow-y-auto pr-2 custom-scrollbar">
          <div className="space-y-6 text-white">
            <div className="px-2">
              <h3 className="text-gray-400 mb-4">DEVICE</h3>
              <div className="space-y-2">
                <div className="flex justify-between">
                  <span>Name</span>
                  <span>{hostname || flowData.device?.name}</span>
                </div>
                <div className="flex justify-between">
                  <span>IP Address</span>
                  <span>{flowData.device?.ipAddress}</span>
                </div>
                <div className="flex justify-between">
                  <span>Port</span>
                  <span>{flowData.device?.port}</span>
                </div>
                <div className="flex justify-between">
                  <span>MAC Address</span>
                  <span>{flowData.device?.macAddress}</span>
                </div>
                <div className="flex justify-between">
                  <span>Vendor</span>
                  <span>{vendor || 'Unknown'}</span>
                </div>
              </div>
            </div>

            <div className="px-2">
              <h3 className="text-gray-400 mb-4">DESTINATION</h3>
              <div className="space-y-2">
                <div className="flex justify-between">
                  <span>Name</span>
                  <span>{flowData.destination?.name}</span>
                </div>
                <div className="flex justify-between items-center">
                  <span>IP Address</span>
                  <button
                    onClick={() => setShowIpDetails(!showIpDetails)}
                    className="flex items-center gap-2 text-dashboard-accent hover:text-dashboard-accent/80 transition-colors"
                  >
                    <MapPin className="w-4 h-4" />
                    <span>{flowData.destination?.ipAddress}</span>
                    {showIpDetails ? <ChevronUp className="w-4 h-4" /> : <ChevronDown className="w-4 h-4" />}
                  </button>
                </div>
                
                {showIpDetails && (
                  <div className="mt-4 p-4 bg-dashboard-background/50 rounded-lg border border-gray-800 space-y-3">
                    {isLoadingIp ? (
                      <div className="text-center text-gray-400">Loading IP details...</div>
                    ) : ipLookup ? (
                      <>
                        <div className="grid grid-cols-2 gap-2 text-sm">
                          <div className="text-gray-400">Country:</div>
                          <div>{ipLookup.country}</div>
                          <div className="text-gray-400">Continent:</div>
                          <div>{ipLookup.continent}</div>
                          <div className="text-gray-400">Timezone:</div>
                          <div className="text-xs">{ipLookup.timezone}</div>
                          <div className="text-gray-400">ASN:</div>
                          <div>{ipLookup.asn}</div>
                          <div className="text-gray-400">Organization:</div>
                          <div className="text-xs">{ipLookup.asnOrganization}</div>
                          <div className="text-gray-400">Network:</div>
                          <div className="text-xs">{ipLookup.asnNetwork}</div>
                        </div>
                        
                        {ipLookup.latitude && ipLookup.longitude && (
                          <div className="mt-4">
                            <div className="text-gray-400 text-sm mb-2">Location Map</div>
                            <div className="w-full h-48 rounded-lg overflow-hidden border border-gray-700">
                              <iframe
                                width="100%"
                                height="100%"
                                frameBorder="0"
                                scrolling="no"
                                marginHeight={0}
                                marginWidth={0}
                                src={`https://www.openstreetmap.org/export/embed.html?bbox=${parseFloat(ipLookup.longitude) - 0.5},${parseFloat(ipLookup.latitude) - 0.5},${parseFloat(ipLookup.longitude) + 0.5},${parseFloat(ipLookup.latitude) + 0.5}&layer=mapnik&marker=${ipLookup.latitude},${ipLookup.longitude}`}
                              />
                            </div>
                            <div className="text-xs text-gray-400 mt-1">
                              Coordinates: {ipLookup.latitude}, {ipLookup.longitude}
                            </div>
                          </div>
                        )}
                      </>
                    ) : (
                      <div className="text-center text-red-400">Failed to load IP details</div>
                    )}
                  </div>
                )}
                
                <div className="flex justify-between">
                  <span>Port</span>
                  <span>{flowData.destination?.port}</span>
                </div>
                {flowData.destination?.protocol && (
                  <div className="bg-[#222632] p-2 rounded text-sm">
                    <span>{flowData.destination.protocol}</span>
                  </div>
                )}
              </div>
            </div>

            <div className="px-2">
              <h3 className="text-gray-400 mb-4">CATEGORIES</h3>
              <div className="space-y-2">
                <div className="flex justify-between">
                  <span>Application</span>
                  <span>{flowData.categories?.application}</span>
                </div>
                <div className="flex justify-between">
                  <span>Domain</span>
                  <span>{flowData.categories?.domain}</span>
                </div>
                <div className="flex justify-between">
                  <span>Protocol</span>
                  <span>{flowData.categories?.protocol}</span>
                </div>
              </div>
            </div>

            <div className="px-2">
              <h3 className="text-gray-400 mb-4">DETECTION</h3>
              <div className="space-y-2">
                <div className="flex justify-between">
                  <span>Application ID</span>
                  <span>{flowData.detection?.application}</span>
                </div>
                <div className="flex justify-between">
                  <span>Application Name</span>
                  <span>{flowData.detection?.applicationName}</span>
                </div>
                <div className="flex justify-between">
                  <span>Protocol ID</span>
                  <span>{flowData.detection?.protocol}</span>
                </div>
                <div className="flex justify-between">
                  <span>Protocol Name</span>
                  <span>{flowData.detection?.protocolName}</span>
                </div>
                <div className="flex justify-between">
                  <span>Detection Guessed</span>
                  <span>{flowData.detection?.guessed ? 'Yes' : 'No'}</span>
                </div>
                {flowData.detection?.hostnames?.dns && (
                  <div className="flex justify-between">
                    <span>DNS Hostname</span>
                    <span className="text-right break-all">{flowData.detection.hostnames.dns}</span>
                  </div>
                )}
                {flowData.detection?.hostnames?.server && (
                  <div className="flex justify-between">
                    <span>Server Hostname</span>
                    <span className="text-right break-all">{flowData.detection.hostnames.server}</span>
                  </div>
                )}
              </div>
            </div>

            <div className="px-2">
              <h3 className="text-gray-400 mb-4">FLOW DETAIL</h3>
              <div className="space-y-2">
                <div className="flex justify-between">
                  <span>Timestamp</span>
                  <span>{flowData.details?.timestamp}</span>
                </div>
                <div className="flex justify-between">
                  <span>Direction</span>
                  <span>{flowData.details?.direction}</span>
                </div>
                <div className="flex justify-between">
                  <span>Outbound Interface</span>
                  <span>{flowData.details?.outboundInterface}</span>
                </div>
                <div className="flex justify-between">
                  <span>Flow Count</span>
                  <span>{flowData.details?.flowCount}</span>
                </div>
                
                {isLoadingUsage && (
                  <div className="flex justify-center py-2">
                    <span className="text-gray-400">Loading usage data...</span>
                  </div>
                )}
                
                {isErrorUsage && (
                  <div className="flex justify-center py-2">
                    <span className="text-red-400">Error loading usage data</span>
                  </div>
                )}
                
                {!isLoadingUsage && !isErrorUsage && (
                  <>
                    {flowUsage ? (
                      <>
                        <div className="flex justify-between">
                          <span>Local Bytes</span>
                          <span>{flowUsage.formattedLocalBytes}</span>
                        </div>
                        <div className="flex justify-between">
                          <span>Other Bytes</span>
                          <span>{flowUsage.formattedOtherBytes}</span>
                        </div>
                        <div className="flex justify-between">
                          <span>Total Bytes</span>
                          <span>{flowUsage.formattedTotalBytes}</span>
                        </div>
                      </>
                    ) : (
                      <div className="flex justify-center py-2">
                        <span className="text-gray-400">No usage data available</span>
                      </div>
                    )}
                  </>
                )}
                
                {digestValue && (
                  <div className="flex justify-between">
                    <span>Digest</span>
                    <span className="text-xs text-gray-400 break-all">{digestValue}</span>
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>

        <div className="hidden flex justify-between gap-4 pt-4 px-2 mt-4 border-t border-gray-800">
          <Button 
            className="flex-1 bg-blue-500 hover:bg-blue-600"
            onClick={() => {
              // TODO: Implement route action
              console.log("Route clicked");
            }}
          >
            Route
          </Button>
          <Button 
            className="flex-1 bg-red-500 hover:bg-red-600"
            onClick={() => {
              // TODO: Implement block action
              console.log("Block clicked");
            }}
          >
            Block
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
