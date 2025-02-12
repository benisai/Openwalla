import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { FlowDetailsData } from "@/misc/types/flow";
import { useQuery } from "@tanstack/react-query";

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

export function FlowDetailsDialog({ open, onOpenChange, flowData }: FlowDetailsProps) {
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
                <div className="flex justify-between">
                  <span>IP Address</span>
                  <span>{flowData.destination?.ipAddress}</span>
                </div>
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
