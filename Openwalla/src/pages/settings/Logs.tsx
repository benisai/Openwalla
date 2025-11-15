import { useState, useEffect, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import { ChevronLeft, Home, Download, Trash2 } from 'lucide-react';
import { Switch } from '@/components/ui/switch';
import { Label } from '@/components/ui/label';

const LogViewer = ({ type }: { type: 'backend' | 'frontend' }) => {
  const [logs, setLogs] = useState<string>('');
  const [isAutoScroll, setIsAutoScroll] = useState(true);
  const [isTailing, setIsTailing] = useState(false);
  const scrollRef = useRef<HTMLDivElement>(null);
  const eventSourceRef = useRef<EventSource | null>(null);

  // Load initial logs
  useEffect(() => {
    loadLogs();
  }, [type]);

  // Auto-scroll to bottom
  useEffect(() => {
    if (isAutoScroll && scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [logs, isAutoScroll]);

  // Tail logs
  useEffect(() => {
    if (isTailing) {
      startTailing();
    } else {
      stopTailing();
    }

    return () => {
      stopTailing();
    };
  }, [isTailing, type]);

  const loadLogs = async () => {
    try {
      const response = await fetch(`/api/logs/${type}?lines=500`);
      const data = await response.json();
      setLogs(data.content || 'No logs available');
    } catch (error) {
      console.error('Error loading logs:', error);
      setLogs('Error loading logs');
    }
  };

  const startTailing = () => {
    stopTailing();

    const eventSource = new EventSource(`/api/logs/${type}/tail`);
    eventSourceRef.current = eventSource;

    eventSource.onmessage = (event) => {
      const data = JSON.parse(event.data);
      
      if (data.type === 'log') {
        setLogs(prev => prev + '\n' + data.message);
      } else if (data.type === 'info') {
        setLogs(prev => prev + '\n[INFO] ' + data.message);
      } else if (data.type === 'error') {
        setLogs(prev => prev + '\n[ERROR] ' + data.message);
      }
    };

    eventSource.onerror = (error) => {
      console.error('EventSource error:', error);
      stopTailing();
      setIsTailing(false);
    };
  };

  const stopTailing = () => {
    if (eventSourceRef.current) {
      eventSourceRef.current.close();
      eventSourceRef.current = null;
    }
  };

  const downloadLogs = () => {
    const blob = new Blob([logs], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${type}-logs-${new Date().toISOString()}.txt`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  };

  const clearLogs = () => {
    setLogs('');
  };

  return (
    <div className="space-y-4">
      <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
        <div className="flex flex-wrap items-center gap-4">
          <div className="flex items-center gap-2">
            <Switch
              id={`tail-${type}`}
              checked={isTailing}
              onCheckedChange={setIsTailing}
            />
            <Label htmlFor={`tail-${type}`} className="text-white">Live Tail</Label>
          </div>
          <div className="flex items-center gap-2">
            <Switch
              id={`autoscroll-${type}`}
              checked={isAutoScroll}
              onCheckedChange={setIsAutoScroll}
            />
            <Label htmlFor={`autoscroll-${type}`} className="text-white">Auto Scroll</Label>
          </div>
        </div>
        <div className="flex gap-2">
          <button 
            onClick={loadLogs}
            className="px-3 py-1 text-sm bg-dashboard-card border border-gray-800 rounded hover:bg-gray-700 text-white"
          >
            Refresh
          </button>
          <button 
            onClick={downloadLogs}
            className="px-3 py-1 text-sm bg-dashboard-card border border-gray-800 rounded hover:bg-gray-700 text-white flex items-center gap-2"
          >
            <Download className="h-4 w-4" />
            Download
          </button>
          <button 
            onClick={clearLogs}
            className="px-3 py-1 text-sm bg-dashboard-card border border-gray-800 rounded hover:bg-gray-700 text-white flex items-center gap-2"
          >
            <Trash2 className="h-4 w-4" />
            Clear
          </button>
        </div>
      </div>

      <div className="bg-dashboard-card rounded-lg border border-gray-800 h-[500px] sm:h-[600px] overflow-hidden">
        <div
          ref={scrollRef}
          className="p-4 font-mono text-xs sm:text-sm whitespace-pre-wrap break-all overflow-auto h-full custom-scrollbar text-gray-300"
        >
          {logs || 'No logs to display'}
        </div>
      </div>
    </div>
  );
};

export default function Logs() {
  const navigate = useNavigate();
  const [activeTab, setActiveTab] = useState<'backend' | 'frontend'>('backend');

  return (
    <div className="min-h-screen bg-dashboard-background text-white p-4">
      <div className="max-w-4xl mx-auto">
        <header className="flex items-center justify-between mb-6">
          <button
            onClick={() => navigate('/settings')}
            className="text-dashboard-accent hover:opacity-80"
          >
            <ChevronLeft className="w-6 h-6" />
          </button>
          <h1 className="text-xl font-bold">System Logs</h1>
          <button
            onClick={() => navigate("/")}
            className="text-dashboard-accent hover:opacity-80"
          >
            <Home className="w-6 h-6" />
          </button>
        </header>

        <div className="space-y-4">
          <div className="bg-dashboard-card rounded-lg overflow-hidden">
            <div className="border-b border-gray-800">
              <div className="grid grid-cols-2">
                <button
                  onClick={() => setActiveTab('backend')}
                  className={`p-4 text-center font-medium transition-colors ${
                    activeTab === 'backend'
                      ? 'bg-gray-700 text-white border-b-2 border-dashboard-accent'
                      : 'text-gray-400 hover:text-white hover:bg-gray-800'
                  }`}
                >
                  Backend
                </button>
                <button
                  onClick={() => setActiveTab('frontend')}
                  className={`p-4 text-center font-medium transition-colors ${
                    activeTab === 'frontend'
                      ? 'bg-gray-700 text-white border-b-2 border-dashboard-accent'
                      : 'text-gray-400 hover:text-white hover:bg-gray-800'
                  }`}
                >
                  Frontend
                </button>
              </div>
            </div>
            
            <div className="p-4">
              {activeTab === 'backend' && <LogViewer type="backend" />}
              {activeTab === 'frontend' && <LogViewer type="frontend" />}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
