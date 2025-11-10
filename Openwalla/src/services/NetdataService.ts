

export interface SystemMetrics {
  cpu: number;
  memory: number;
  load: number;
  received: number;
  sent: number;
  connections: number;
}

export const fetchSystemMetrics = async (): Promise<SystemMetrics> => {
  const response = await fetch('/api/netdata/metrics');
  
  if (!response.ok) {
    throw new Error('Failed to fetch metrics');
  }

  const result = await response.json();
  
  if (!result.success) {
    throw new Error(result.error || 'Failed to fetch metrics');
  }

  return result.data;
};

