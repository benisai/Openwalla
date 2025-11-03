// src/services/useSpeedTest.ts

import { useState, useCallback, useRef, useEffect } from 'react';
import SpeedTest from '@cloudflare/speedtest';
import axios from 'axios';

// Type definitions remain the same
export interface TestResult {
  latency?: number;
  download?: number;
  upload?: number;
  status: 'idle' | 'running' | 'finished' | 'error';
  progress?: string;
}

const INITIAL_STATE: TestResult = {
  status: 'idle',
  latency: undefined,
  download: undefined,
  upload: undefined,
  progress: 'Ready to test.',
};

const API_BASE_URL = '/api/speedtest'; 

const saveResultsToDb = async (results: TestResult) => {
    if (results.download === undefined || results.upload === undefined || results.latency === undefined) {
        console.error('Cannot save results: Missing download, upload, or latency data.');
        return;
    }

    try {
        await axios.post(`${API_BASE_URL}/save`, {
            latency: results.latency,
            download: results.download,
            upload: results.upload,
            status: 'finished', 
        });
        console.log('✅ Speed test results successfully sent to API.');
    } catch (error) {
        console.error('❌ Failed to save speed test results via API:', error);
    }
};


export const useSpeedTest = () => {
  const [results, setResults] = useState<TestResult>(INITIAL_STATE);
  const testRef = useRef<SpeedTest | null>(null);
  const saveSentRef = useRef<boolean>(false); 

  // Cleanup function to stop the test and clear the ref
  const cleanupTest = useCallback(() => {
    if (testRef.current) {
        // 👈 FIX 1: Safely check for the abort method before calling it.
        // The Cloudflare library uses .abort() to stop the test and clean up resources
        if (typeof (testRef.current as any).abort === 'function') {
             console.log('Aborting/Cleaning up speed test instance.');
             (testRef.current as any).abort(); 
        } else {
             console.log('SpeedTest instance found, but abort() method is missing/invalid. Clearing reference.');
        }
        testRef.current = null; // Clear the reference regardless
    }
  }, []);

  // Cleanup on unmount
  useEffect(() => {
      return () => {
          cleanupTest();
      };
  }, [cleanupTest]); 


  const startTest = useCallback(() => {
    cleanupTest();
    saveSentRef.current = false;
    setResults({ ...INITIAL_STATE, status: 'running', progress: 'Starting test...' });

    let test: SpeedTest | null = null;
    try {
        // Attempt to create the instance
        test = new SpeedTest();
        testRef.current = test; // Store the new instance
    } catch (e) {
        // Catch immediate failure during instantiation
        console.error('Failed to instantiate SpeedTest:', e);
        setResults(prev => ({ 
            ...prev, 
            status: 'error', 
            progress: `Error starting test: ${e instanceof Error ? e.message : 'Instantiation failed.'}` 
        }));
        return; // Stop execution if instantiation fails
    }


    test.onFinish = (cloudflareResults) => {
      // FIX 2: Single-save logic prevents multiple DB inserts
      if (saveSentRef.current) {
          console.log('Ignoring duplicate onFinish event.');
          cleanupTest();
          return;
      }
      saveSentRef.current = true; // Set flag to prevent future saves

      const summary = cloudflareResults.getSummary();
      
      setResults((prev) => {
          const finalResults: TestResult = {
              ...prev,
              latency: summary.latency,
              download: summary.download,
              upload: summary.upload,
              progress: 'Test complete!',
              status: 'finished', 
          };
          
          saveResultsToDb(finalResults); 
          
          return finalResults;
      });
      
      cleanupTest();
    };
    
    test.onResultsChange = (change) => {
      const typeText = change.type.charAt(0).toUpperCase() + change.type.slice(1);
      setResults(prev => ({ 
          ...prev, 
          progress: `Running: ${typeText} phase...` 
      }));
    };

    test.onError = (error: unknown) => {
        console.error("Speed test error:", error);
        const errorMessage = error instanceof Error ? error.message : String(error || 'Unknown error');
        setResults(prev => ({ 
          ...prev, 
          status: 'error', 
          progress: `Error: ${errorMessage}` 
        }));
        
        cleanupTest();
    };

    // 👈 FIX 4: Safely check if the start method exists before calling it.
    if (typeof (test as any).start === 'function') {
        (test as any).start(); 
    } else {
         console.error('SpeedTest instance is missing the .start() method. Test cannot run.');
         setResults(prev => ({ 
            ...prev, 
            status: 'error', 
            progress: 'Error: SpeedTest instance is invalid (missing .start()).'
        }));
        cleanupTest();
    }

  }, [cleanupTest]);

  return { results, startTest };
};
