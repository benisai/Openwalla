import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Separator } from "@/components/ui/separator";
import { Monitor } from "lucide-react";

interface Port {
  number: number;
  description: string;
}

interface PortsDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  ports: Port[];
}

export function PortsDialog({
  open,
  onOpenChange,
  ports,
}: PortsDialogProps) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="bg-dashboard-card border-none max-w-md max-h-[90vh] overflow-hidden flex flex-col">
        <DialogHeader className="pb-4">
          <div className="flex items-center gap-2">
            <div className="p-2 rounded-lg bg-[#2A2F3C]">
              <Monitor className="h-5 w-5 text-dashboard-chart" />
            </div>
            <DialogTitle className="text-white text-xl">Open Ports</DialogTitle>
          </div>
        </DialogHeader>

        <div className="mt-2 flex-1 overflow-y-auto pr-2 custom-scrollbar">
          <div className="space-y-2">
            {ports.map((port, index) => (
              <div key={port.number}>
                <div className="bg-[#2A2F3C] p-4 rounded-lg space-y-3 hover:bg-[#313744] transition-colors duration-200">
                  <div className="flex justify-between items-center">
                    <span className="text-gray-400 font-medium flex items-center gap-2">
                      <div className="h-2 w-2 rounded-full bg-dashboard-chart"></div>
                      Port Number
                    </span>
                    <span className="text-white font-semibold bg-[#222632] px-3 py-1 rounded-md">
                      {port.number}
                    </span>
                  </div>
                  <div className="flex justify-between items-center">
                    <span className="text-gray-400 font-medium flex items-center gap-2">
                      <div className="h-2 w-2 rounded-full bg-dashboard-accent"></div>
                      Description
                    </span>
                    <span className="text-white font-semibold bg-[#222632] px-3 py-1 rounded-md">
                      {port.description}
                    </span>
                  </div>
                </div>
                {index < ports.length - 1 && (
                  <Separator className="my-2 bg-gray-800" />
                )}
              </div>
            ))}
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}