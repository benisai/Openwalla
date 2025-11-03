// src/pages/network_performance/components/InternetSpeedCard.tsx

import React, { useState, useEffect } from 'react';
import axios from 'axios';
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { ChevronRight, Globe, ArrowDown, ArrowUp } from "lucide-react";
import { LineChart, Line, XAxis, YAxis, CartesianGrid, ResponsiveContainer, Tooltip } from 'recharts';
// import { WANTestOptions } from "./WANTestOptions";
import { useSpeedTest } from '@/services/useSpeedTest'; 

// Define the shape of the data returned by the API
interface HistoricalRecord {
    download: number;
    upload: number;
    latency: number; 
    timestamp: string;
    name?: string; // For recharts XAxis label
}

const API_HISTORY_URL = '/api/speedtest/history';

// Helper function for cleaner speed formatting and BPS to MBPS conversion
const formatSpeed = (speed: number | undefined) => {
    if (speed === undefined) return '--';
    const mbps = speed / 1000000;
    return mbps.toFixed(mbps < 10 ? 2 : 1);
};

/**
 * Helper function to remove records that have identical download, upload, and latency
 * values, which arise from simultaneous database insertions.
 */
const filterDuplicates = (data: HistoricalRecord[]): HistoricalRecord[] => {
    const uniqueMap = new Map<string, HistoricalRecord>();
    
    // Iterate from newest to oldest to ensure we keep the LATEST timestamp 
    // for any set of duplicate speed results.
    for (let i = data.length - 1; i >= 0; i--) {
        const item = data[i];
        
        // Create a unique key based on the essential data fields (to 2 decimal places for robustness)
        const key = `${item.latency.toFixed(2)}_${item.download.toFixed(2)}_${item.upload.toFixed(2)}`;
        
        if (!uniqueMap.has(key)) {
            uniqueMap.set(key, item);
        }
    }
    
    // Convert map values back to an array and sort by timestamp to maintain chart order (oldest to newest)
    return Array.from(uniqueMap.values()).sort((a, b) => new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime());
};


// Custom Tooltip Component for detailed date/time info on hover
const CustomTooltip = ({ active, payload }: any) => {
    if (active && payload && payload.length) {
        const dataPoint: HistoricalRecord = payload[0].payload;
        
        if (dataPoint.download === undefined || dataPoint.upload === undefined) return null;

        const fullDateTime = new Date(dataPoint.timestamp).toLocaleString();
        
        const downloadValue = formatSpeed(dataPoint.download);
        const uploadValue = formatSpeed(dataPoint.upload);
        
        const rawLatency = dataPoint.latency;
        const latencyValue = rawLatency !== undefined ? rawLatency.toFixed(0) : '--';

        return (
            <div className="bg-dashboard-card border border-gray-700 p-3 text-sm shadow-lg rounded">
                <p className="text-gray-400 font-semibold mb-1">{fullDateTime}</p>
                <p className="text-blue-400">Download: <span className="font-semibold">{downloadValue} Mb/s</span></p>
                <p className="text-red-400">Upload: <span className="font-semibold">{uploadValue} Mb/s</span></p>
                <p className="text-gray-400">Latency: <span className="font-semibold">{latencyValue} ms</span></p>
            </div>
        );
    }

    return null;
};


export function InternetSpeedCard() {
    const [isTestOptionsOpen, setIsTestOptionsOpen] = useState(false);
    const { results, startTest } = useSpeedTest();
    const { download, upload, status } = results; 

    const [history, setHistory] = useState<HistoricalRecord[]>([]);
    const [lastTestTime, setLastTestTime] = useState<string>('N/A');
    const [isLoadingHistory, setIsLoadingHistory] = useState(true);

    const [latestLoadedResult, setLatestLoadedResult] = useState<{ download: number | undefined, upload: number | undefined }>({ download: undefined, upload: undefined });
    
    // Cooldown logic removed

    const isTesting = status === 'running';

    const fetchHistory = async () => {
        setIsLoadingHistory(true);
        try {
            const response = await axios.get(API_HISTORY_URL);
            const rawData: HistoricalRecord[] = response.data;
            
            const uniqueData = filterDuplicates(rawData);
            
            setHistory(uniqueData.map(item => ({
                ...item,
                name: new Date(item.timestamp).toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' }), 
            })));

            if (uniqueData.length > 0) {
                const latestRecord = uniqueData[uniqueData.length - 1]; 
                const latestTimestamp = latestRecord.timestamp; 
                
                // Fix for timestamp parsing using browser time
                const cleanTimestamp = latestTimestamp
                    .replace(' ', 'T')       
                    .replace(/\s?\+0000/, 'Z')
                    .trim();
                
                const latestTestDate = new Date(cleanTimestamp);
                
                setLatestLoadedResult({
                    download: latestRecord.download,
                    upload: latestRecord.upload,
                });
                
                setLastTestTime(latestTestDate.toLocaleString());
            } else {
                setLatestLoadedResult({ download: undefined, upload: undefined });
                setLastTestTime('No successful tests recorded.');
            }
        } catch (error) {
            console.error('Error fetching speed test history:', error);
            setLatestLoadedResult({ download: undefined, upload: undefined });
            setLastTestTime('Failed to load history.');
        } finally {
            setIsLoadingHistory(false);
        }
    };

    // Fetch data on mount and whenever the speed test finishes
    useEffect(() => {
        fetchHistory();
    }, [status]); 

    const getStatusText = () => {
        switch (status) {
        case 'idle':
            return 'Ready to run speed test.';
        case 'running':
            return results.progress || 'Testing in progress...';
        case 'finished':
            return `Last test finished successfully.`; 
        case 'error':
            return results.progress || 'An error occurred during the test.';
        default:
            return 'Status unknown.';
        }
    };

    const isTestActiveOrFinished = status !== 'idle' && status !== 'error';
    const displayDownload = isTestActiveOrFinished ? download : latestLoadedResult.download;
    const displayUpload = isTestActiveOrFinished ? upload : latestLoadedResult.upload;

    // 🚀 FIX: The button should ONLY be disabled if the status is explicitly 'running'.
    // It will be enabled for 'idle', 'finished', and 'error'.
    const isButtonDisabled = isTesting;
    
    const buttonText = () => {
        if (isTesting) {
            return `Testing... ${formatSpeed(displayDownload)} Mb/s`;
        }
        return 'Test Internet Speed';
    }


    return (
        <Card className="bg-dashboard-card text-white">
        <CardHeader className="flex flex-row items-center justify-between">
            <div className="flex items-center gap-2">
            <Globe className="h-5 w-5" />
            <CardTitle className="text-xl">WAN Performance</CardTitle>
            </div>
        </CardHeader>
        <CardContent className="space-y-6">
            <div className="grid grid-cols-2 gap-4">
            <div>
                <div className="flex items-center gap-2">
                <ArrowDown className="h-4 w-4 text-blue-400" />
                <span className="text-gray-400">Download</span>
                </div>
                <p className="text-base md:text-2xl font-bold">{formatSpeed(displayDownload)} Mb/s</p>
            </div>
            <div>
                <div className="flex items-center gap-2">
                <ArrowUp className="h-4 w-4 text-red-400" />
                <span className="text-gray-400">Upload</span>
                </div>
                <p className="text-base md:text-2xl font-bold">{formatSpeed(displayUpload)} Mb/s</p>
            </div>
            </div>
            
            {/* Display dynamic status */}
            <p className={`text-sm ${status === 'error' ? 'text-red-400' : 'text-gray-400'}`}>
            Status: {getStatusText()}
            </p>

            {/* Display last successful test time */}
            <p className="text-sm text-gray-400">
                History loaded. Last test recorded: {lastTestTime}
            </p>

            {/* Chart JSX */}
            <div className="h-64 w-full">
                {isLoadingHistory ? (
                    <div className="h-full flex items-center justify-center text-gray-500">Loading historical data...</div>
                ) : history.length === 0 ? (
                    <div className="h-full flex items-center justify-center text-gray-500">No test data available. Run a speed test!</div>
                ) : (
                    <ResponsiveContainer width="100%" height="100%">
                        <LineChart data={history}>
                            <CartesianGrid strokeDasharray="3 3" stroke="#374151" />
                            <XAxis dataKey="name" stroke="#9CA3AF" />
                            <YAxis stroke="#9CA3AF" />
                            <Tooltip content={<CustomTooltip />} />
                            <Line type="monotone" dataKey="download" stroke="#3B82F6" strokeWidth={2} dot={{ fill: "#3B82F6" }} />
                            <Line type="monotone" dataKey="upload" stroke="#EF4444" strokeWidth={2} dot={{ fill: "#EF4444" }} />
                        </LineChart>
                    </ResponsiveContainer>
                )}
            </div>
            
            <button 
            className={`w-full py-2 font-semibold transition-colors rounded-lg ${
                isButtonDisabled 
                ? 'bg-gray-600 text-gray-400 cursor-not-allowed' 
                : 'bg-blue-600 hover:bg-blue-500 text-white'
            }`}
            onClick={startTest}
            disabled={isButtonDisabled}
            >
            {buttonText()}
            </button>
        </CardContent>
        
        </Card>
    );
}
