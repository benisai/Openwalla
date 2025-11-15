import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { ArrowLeft, Loader2, CheckCircle, XCircle } from "lucide-react";
import { toast } from "sonner";
import axios from "axios";
import { ScrollArea } from "@/components/ui/scroll-area";

interface TestResult {
  success: boolean;
  message?: string;
  data?: any;
  error?: string;
}

export default function OpenWRTFunctions() {
  const navigate = useNavigate();
  const [testResults, setTestResults] = useState<Record<string, TestResult>>({});
  const [loading, setLoading] = useState<Record<string, boolean>>({});

  const functions = [
    {
      id: "test-connection",
      name: "Test Connection",
      description: "Test connection and authentication to OpenWRT router",
      endpoint: "/api/openwrt/test-connection",
      method: "GET"
    },
    {
      id: "router-status",
      name: "Router Status",
      description: "Get current router status and connectivity",
      endpoint: "/api/openwrt/status",
      method: "GET"
    },
    {
      id: "system-info",
      name: "System Information",
      description: "Retrieve system information from the router",
      endpoint: "/api/openwrt/system-info",
      method: "GET"
    },
    {
      id: "network-interfaces",
      name: "Network Interfaces",
      description: "Get network interface configuration",
      endpoint: "/api/openwrt/network",
      method: "GET"
    },
    {
      id: "wireless-config",
      name: "Wireless Configuration",
      description: "Retrieve wireless network settings",
      endpoint: "/api/openwrt/wireless",
      method: "GET"
    }
  ];

  const executeFunction = async (func: typeof functions[0]) => {
    setLoading((prev) => ({ ...prev, [func.id]: true }));
    setTestResults((prev) => ({ ...prev, [func.id]: { success: false, message: "Testing..." } }));

    try {
      const response = await axios({
        method: func.method,
        url: func.endpoint,
      });

      const result: TestResult = {
        success: true,
        message: "Function executed successfully",
        data: response.data
      };

      setTestResults((prev) => ({ ...prev, [func.id]: result }));
      toast.success(`${func.name} executed successfully`);
    } catch (error: any) {
      const result: TestResult = {
        success: false,
        message: "Function execution failed",
        error: error.response?.data?.message || error.message
      };

      setTestResults((prev) => ({ ...prev, [func.id]: result }));
      toast.error(`${func.name} failed: ${result.error}`);
    } finally {
      setLoading((prev) => ({ ...prev, [func.id]: false }));
    }
  };

  const getStatusIcon = (functionId: string) => {
    const result = testResults[functionId];
    const isLoading = loading[functionId];

    if (isLoading) {
      return <Loader2 className="h-4 w-4 animate-spin text-blue-500" />;
    }
    if (!result) {
      return null;
    }
    if (result.success) {
      return <CheckCircle className="h-4 w-4 text-green-500" />;
    }
    return <XCircle className="h-4 w-4 text-red-500" />;
  };

  return (
    <div className="min-h-screen bg-background p-6">
      <div className="max-w-6xl mx-auto space-y-6">
        {/* Header */}
        <div className="flex items-center gap-4">
          <Button
            variant="ghost"
            onClick={() => navigate("/settings")}
            className="text-foreground hover:text-foreground/80"
          >
            <ArrowLeft className="h-4 w-4 mr-2" />
            Back to Settings
          </Button>
        </div>

        <div>
          <h1 className="text-3xl font-bold text-foreground">OpenWRT Functions</h1>
          <p className="text-muted-foreground mt-2">
            Test and execute OpenWRT API functions
          </p>
        </div>

        {/* Functions Grid */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          {functions.map((func) => (
            <Card key={func.id} className="bg-card border-border p-6 space-y-4">
              <div className="flex items-start justify-between">
                <div className="space-y-1 flex-1">
                  <h3 className="text-lg font-semibold text-foreground">{func.name}</h3>
                  <p className="text-sm text-muted-foreground">{func.description}</p>
                  <p className="text-xs text-muted-foreground/60 font-mono">
                    {func.method} {func.endpoint}
                  </p>
                </div>
                <div className="ml-4">{getStatusIcon(func.id)}</div>
              </div>

              <Button
                onClick={() => executeFunction(func)}
                disabled={loading[func.id]}
                className="w-full"
                variant="outline"
              >
                {loading[func.id] ? (
                  <>
                    <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                    Testing...
                  </>
                ) : (
                  "Execute Function"
                )}
              </Button>

              {/* Result Display */}
              {testResults[func.id] && (
                <div className="mt-4 p-4 bg-muted/50 rounded-lg">
                  <div className="text-sm space-y-2">
                    <div className="flex items-center gap-2">
                      <span className="font-medium text-foreground">Status:</span>
                      <span
                        className={
                          testResults[func.id].success
                            ? "text-green-500"
                            : "text-red-500"
                        }
                      >
                        {testResults[func.id].success ? "Success" : "Failed"}
                      </span>
                    </div>
                    {testResults[func.id].message && (
                      <div>
                        <span className="font-medium text-foreground">Message:</span>
                        <p className="text-muted-foreground mt-1">
                          {testResults[func.id].message}
                        </p>
                      </div>
                    )}
                    {testResults[func.id].error && (
                      <div>
                        <span className="font-medium text-foreground">Error:</span>
                        <p className="text-red-500 mt-1">{testResults[func.id].error}</p>
                      </div>
                    )}
                    {testResults[func.id].data && (
                      <div className="mt-2">
                        <span className="font-medium text-foreground">Response Data:</span>
                        <ScrollArea className="h-32 w-full mt-2">
                          <pre className="text-xs text-muted-foreground overflow-auto p-2 bg-background rounded">
                            {JSON.stringify(testResults[func.id].data, null, 2)}
                          </pre>
                        </ScrollArea>
                      </div>
                    )}
                  </div>
                </div>
              )}
            </Card>
          ))}
        </div>
      </div>
    </div>
  );
}
