import { Button } from "@/components/ui/button";

interface FlowsProtocolFilterProps {
  uniqueProtocols: string[];
  selectedProtocol: string | null;
  setSelectedProtocol: (protocol: string | null) => void;
}

export const FlowsProtocolFilter = ({ 
  uniqueProtocols, 
  selectedProtocol, 
  setSelectedProtocol 
}: FlowsProtocolFilterProps) => {
  return (
    <div className="flex flex-wrap justify-center gap-3 mb-6">
      <Button
        key="all"
        variant="outline"
        className={`bg-gray-800/50 border-gray-700 hover:bg-gray-700/50 whitespace-nowrap ${
          !selectedProtocol ? 'ring-2 ring-blue-500' : ''
        }`}
        onClick={() => setSelectedProtocol(null)}
      >
        All Protocols
      </Button>
      {uniqueProtocols.map((protocol) => (
        <Button
          key={protocol}
          variant="outline"
          className={`bg-gray-800/50 border-gray-700 hover:bg-gray-700/50 whitespace-nowrap ${
            selectedProtocol === protocol ? 'ring-2 ring-blue-500' : ''
          }`}
          onClick={() => setSelectedProtocol(protocol)}
        >
          {protocol}
        </Button>
      ))}
    </div>
  );
};