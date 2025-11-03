
import { useState } from "react";
import { ArrowLeft, Trash2 } from "lucide-react";
import { useNavigate, useParams } from "react-router-dom";
import { Button } from "@/components/ui/button";
import { DeviceNameDialog } from "@/pages/devices/components/DeviceNameDialog";
import { IpAllocationDialog } from "@/pages/devices/components/IpAllocationDialog";
import { useDevice, useDeleteDevice } from "@/services/DeviceService";
import { useToast } from "@/components/ui/use-toast";
import { DeviceThroughputGraph } from "@/pages/devices/components/DeviceThroughputGraph";
import { useQuery } from "@tanstack/react-query";
import { getDeviceFlowCount } from "@/services/FlowService";
import { useUpdateDeviceHostname } from "@/services/DeviceService";
import { DeviceInfoCard } from "@/pages/devices/components/DeviceInfoCard";
import { DeviceUsageStats } from "@/pages/devices/components/DeviceUsageStats";
import { DeviceTopTables } from "@/pages/devices/components/DeviceTopTables";
import { DeviceApplicationUsage } from "@/pages/devices/components/DeviceApplicationUsage";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";

const DeviceDetails = () => {
  const navigate = useNavigate();
  const { id } = useParams();
  const { data: device, isLoading, error } = useDevice(id ?? '');
  const { toast } = useToast();
  const updateHostname = useUpdateDeviceHostname();
  const deleteDevice = useDeleteDevice();
  
  const [nameDialogOpen, setNameDialogOpen] = useState(false);
  const [ipDialogOpen, setIpDialogOpen] = useState(false);
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);

  const { data: flowCount = 0 } = useQuery({
    queryKey: ['deviceFlowCount', id],
    queryFn: () => getDeviceFlowCount(id || ''),
    enabled: !!id,
  });

  const handleUpdateHostname = async (newHostname: string) => {
    if (!device) return;
    
    try {
      await updateHostname.mutateAsync({
        mac: device.mac,
        hostname: newHostname
      });
      
      toast({
        title: "Success",
        description: "Device name updated successfully",
      });
    } catch (err) {
      toast({
        variant: "destructive",
        title: "Error",
        description: "Failed to update device name",
      });
    }
  };

  const handleDeleteDevice = async () => {
    if (!device) return;
    
    try {
      await deleteDevice.mutateAsync(device.mac);
      
      toast({
        title: "Device Deleted",
        description: "Device will reappear on next network scan",
      });
      
      navigate('/devices');
    } catch (err) {
      toast({
        variant: "destructive",
        title: "Error",
        description: "Failed to delete device",
      });
    }
  };

  if (error) {
    toast({
      variant: "destructive",
      title: "Error",
      description: "Failed to fetch device details"
    });
  }

  if (isLoading || !device) {
    return (
      <div className="min-h-screen bg-dashboard-background text-white p-4">
        <div className="text-center">Loading device details...</div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-dashboard-background text-white">
      <div className="md:max-w-4xl mx-auto p-4 md:px-0">
        <div className="flex items-center mb-6">
          <Button 
            variant="ghost" 
            size="icon"
            onClick={() => navigate(-1)}
            className="mr-2"
          >
            <ArrowLeft className="h-6 w-6 text-dashboard-accent" />
          </Button>
          <h1 className="text-xl font-semibold">{device.hostname}</h1>
        </div>

        <div className="space-y-4 pb-20">
          <DeviceThroughputGraph device={device} />

          <Button
            variant="outline"
            className="w-full bg-dashboard-card hover:bg-gray-800"
            onClick={() => navigate(`/device-flows/${device.mac}`)}
          >
            Flows ({flowCount.toLocaleString()})
          </Button>

          <DeviceUsageStats device={device} />

          <DeviceInfoCard 
            device={device}
            onNameClick={() => setNameDialogOpen(true)}
            onIpClick={() => setIpDialogOpen(true)}
          />
          
          {/* Add the Application Usage Section */}
          <DeviceApplicationUsage deviceMac={device.mac} />

          <DeviceTopTables deviceMac={device.mac} />

          <Button
            variant="destructive"
            className="w-full mt-6"
            onClick={() => setDeleteDialogOpen(true)}
          >
            <Trash2 className="h-4 w-4 mr-2" />
            Delete This Device
          </Button>
        </div>
      </div>

      <DeviceNameDialog
        open={nameDialogOpen}
        onOpenChange={setNameDialogOpen}
        currentName={device.hostname}
        onSave={handleUpdateHostname}
      />

      <IpAllocationDialog
        open={ipDialogOpen}
        onOpenChange={setIpDialogOpen}
        currentIp={device.ip}
        currentAllocation="dynamic"
        onSave={(allocation, newIp) => console.log('Save IP:', allocation, newIp)}
      />

      <AlertDialog open={deleteDialogOpen} onOpenChange={setDeleteDialogOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete This Device</AlertDialogTitle>
            <AlertDialogDescription>
              This will remove the device from the database. Note: The device will reappear on the next network scan.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={handleDeleteDevice}>
              Delete
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
};

export default DeviceDetails;
