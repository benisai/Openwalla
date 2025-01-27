import { useState, useMemo } from "react";
import { useQuery } from "@tanstack/react-query";
import { getRecentBlockedFlows } from "@/services/FlowService";
import { Flow, FlowDetailsData } from "@/misc/types/flow";
import { format } from "date-fns";
import { FlowDetailsDialog } from "@/pages/flows/components/FlowDetailsDialog";
import { FlowsHeader } from "@/pages/flows/components/FlowsHeader";
import { FlowsTimeSelector } from "@/pages/flows/components/FlowsTimeSelector";
import { FlowsSearch } from "@/pages/flows/components/FlowsSearch";
import { FlowsProtocolFilter } from "@/pages/flows/components/FlowsProtocolFilter";
import { FlowsList } from "@/pages/flows/components/FlowsList";

const BlockedFlows = () => {
  const [selectedTime, setSelectedTime] = useState("1 Hour");
  const [searchQuery, setSearchQuery] = useState("");
  const [selectedProtocol, setSelectedProtocol] = useState<string | null>(null);
  const [selectedFlowDetails, setSelectedFlowDetails] = useState<FlowDetailsData>({});
  const [isDetailsOpen, setIsDetailsOpen] = useState(false);
  
  const timeOptions = [
    "1 Hour",
    "2 Hours",
    "6 Hours",
    "12 Hours",
    "24 Hours"
  ];

  const hoursMap: Record<string, number> = {
    "1 Hour": 1,
    "2 Hours": 2,
    "6 Hours": 6,
    "12 Hours": 12,
    "24 Hours": 24
  };

  const { data: flows = [], isLoading } = useQuery({
    queryKey: ['blocked-flows', selectedTime],
    queryFn: () => getRecentBlockedFlows(hoursMap[selectedTime]),
  });

  const uniqueProtocols = useMemo(() => {
    const protocols = flows.map(flow => flow.detected_protocol_name);
    return Array.from(new Set(protocols)).filter(Boolean);
  }, [flows]);

  const filteredFlows = useMemo(() => {
    return flows.filter(flow => {
      const matchesSearch = searchQuery.toLowerCase() === '' || 
        Object.values(flow).some(value => 
          String(value).toLowerCase().includes(searchQuery.toLowerCase())
        );
      
      const matchesProtocol = !selectedProtocol || 
        flow.detected_protocol_name === selectedProtocol;

      return matchesSearch && matchesProtocol;
    });
  }, [flows, searchQuery, selectedProtocol]);

  const handleFlowClick = (flow: Flow) => {
    const flowDetailsData: FlowDetailsData = {
      device: {
        name: flow.hostname || "Unknown",
        ipAddress: flow.local_ip,
        port: flow.dest_port.toString(),
        macAddress: flow.local_mac,
        vendor: "Unknown"
      },
      destination: {
        name: flow.fqdn || flow.dest_ip,
        ipAddress: flow.dest_ip,
        port: `${flow.detected_protocol_name} ${flow.dest_port}`,
        protocol: flow.detected_protocol_name,
        region: "Unknown"
      },
      details: {
        timestamp: format(new Date(flow.timeinsert), 'MMM d, yyyy \'at\' h:mm a'),
        direction: flow.internal ? "Internal" : "Outbound",
        outboundInterface: flow.interface,
        flowCount: 1,
        duration: "N/A",
        downloaded: "N/A",
        uploaded: "N/A"
      }
    };
    setSelectedFlowDetails(flowDetailsData);
    setIsDetailsOpen(true);
  };

  return (
    <div className="min-h-screen bg-dashboard-background text-white p-4">
      <div className="max-w-4xl mx-auto">
        <FlowsHeader 
          selectedTime={selectedTime}
          setSelectedTime={setSelectedTime}
          timeOptions={timeOptions}
        />

        <FlowsTimeSelector 
          selectedTime={selectedTime}
          setSelectedTime={setSelectedTime}
          timeOptions={timeOptions}
        />

        <div>
          <h2 className="text-gray-400 mb-2">Blocked Flows</h2>
          <div className="text-base md:text-4xl font-bold mb-8">{filteredFlows.length}</div>
        </div>

        <div className="space-y-6">
          <FlowsSearch 
            searchQuery={searchQuery}
            setSearchQuery={setSearchQuery}
          />

          <FlowsProtocolFilter 
            uniqueProtocols={uniqueProtocols}
            selectedProtocol={selectedProtocol}
            setSelectedProtocol={setSelectedProtocol}
          />
        </div>

        {isLoading ? (
          <div className="text-center py-4">Loading flows...</div>
        ) : (
          <FlowsList 
            flows={filteredFlows}
            onFlowClick={handleFlowClick}
          />
        )}
      </div>

      <FlowDetailsDialog 
        open={isDetailsOpen}
        onOpenChange={setIsDetailsOpen}
        flowData={selectedFlowDetails}
      />
    </div>
  );
};

export default BlockedFlows;