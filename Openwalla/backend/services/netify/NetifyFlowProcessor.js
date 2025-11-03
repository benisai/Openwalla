
// This file is called NetifyFlowProcessor.js. It contains the flow type processors

class NetifyFlowProcessor {
  /**
   * Returns the current time in ISO format with timezone offset.
   * This provides a consistent timestamp format that can be properly queried.
   */
  getLocalISOTime() {
    // Use a direct ISO string which includes the timezone information
    // This ensures correct time representation in the database
    return new Date().toISOString();
  }

  /**
   * Extracts the "registered" portion of a client_sni string.
   * Example: "alb.reddit.com" -> "reddit.com"
   * Example: "configuration.apple.com" -> "apple.com"
   */
  extractDomainFromSNI(sni) {
    if (!sni) return null;

    try {
      // Prepend a protocol if missing so the URL constructor can parse it
      let urlString = sni;
      if (!sni.startsWith('http://') && !sni.startsWith('https://')) {
        urlString = 'http://' + sni;
      }
      const url = new URL(urlString);
      const hostname = url.hostname;
      const parts = hostname.split('.');
      if (parts.length >= 2) {
        // Return the last two parts (e.g. "reddit.com")
        return parts.slice(-2).join('.');
      }
      return hostname;
    } catch (err) {
      console.error('[NetifyFlowProcessor] Error extracting domain from SNI:', err);
    }
    return null;
  }

  processFlowData(flowData) {
    if (!flowData || !flowData.type) {
      return null;
    }

    // Handle flow_purge
    if (flowData.type === 'flow_purge') {
      return this.processFlowPurge(flowData);
    }

    // Handle regular flow data (HTTP, HTTP/S, HTTPS)
    if (
      flowData.type === 'flow' &&
      flowData.flow.detected_protocol_name &&
      ['HTTPS', 'HTTP/S', 'HTTP'].includes(flowData.flow.detected_protocol_name)
    ) {
      return this.processRegularFlow(flowData);
    }

    return null;
  }

  processFlowPurge(flowData) {
    return {
      type: 'purge',
      data: {
        // Use ISO time format for consistency
        timeinsert: this.getLocalISOTime(),
        type: flowData.type,
        digest: flowData.flow.digest,
        detection_packets: flowData.flow.detection_packets,
        last_seen_at: flowData.flow.last_seen_at,
        local_bytes: flowData.flow.local_bytes,
        local_packets: flowData.flow.local_packets,
        other_bytes: flowData.flow.other_bytes,
        other_packets: flowData.flow.other_packets,
        total_bytes: flowData.flow.total_bytes,
        total_packets: flowData.flow.total_packets,
        interface: flowData.interface,
        internal: flowData.internal ? 1 : 0,
        reason: flowData.reason || ''
      }
    };
  }

  processRegularFlow(flowData) {
    // Standardize "HTTP/S" to "HTTPS"
    const standardizedProtocol =
      flowData.flow.detected_protocol_name === 'HTTP/S'
        ? 'HTTPS'
        : flowData.flow.detected_protocol_name;

    // Prioritize client_sni for the FQDN if available
    const fqdn = flowData.flow.ssl?.client_sni || flowData.flow.host_server_name || '';

    // Get application name; if it's "" or "Unknown", try to extract from SNI.
    // If an application name is already present (and not "Unknown"), it won't be overridden.
    let detectedAppName = flowData.flow.detected_application_name || '';
    if (
      (detectedAppName === '' || detectedAppName === 'Unknown') &&
      flowData.flow.ssl?.client_sni
    ) {
      const domainName = this.extractDomainFromSNI(flowData.flow.ssl.client_sni);
      if (domainName) {
        // Prefix with "netify." to match the format of other app names
        detectedAppName = `netify.${domainName}`;
      }
    }

    return {
      type: 'flow',
      data: {
        // Use ISO time format for consistency
        timeinsert: this.getLocalISOTime(),
        local_ip: flowData.flow.local_ip,
        local_mac: flowData.flow.local_mac,
        fqdn: fqdn,
        dest_ip: flowData.flow.other_ip,
        dest_port: flowData.flow.other_port,
        dest_type: 'remote',
        detected_protocol_name: standardizedProtocol,
        detected_app_name: detectedAppName,
        interface: flowData.interface,
        internal: flowData.internal ? 1 : 0,
        ndpi_risk_score: flowData.flow.risks?.ndpi_risk_score || 0,
        ndpi_risk_score_client: flowData.flow.risks?.ndpi_risk_score_client || 0,
        ndpi_risk_score_server: flowData.flow.risks?.ndpi_risk_score_server || 0,
        client_sni: flowData.flow.ssl?.client_sni || '',
        category_application: flowData.flow.category?.application || 0,
        category_domain: flowData.flow.category?.domain || 0,
        category_protocol: flowData.flow.category?.protocol || 0,
        detected_application: flowData.flow.detected_application || 0,
        detected_protocol: flowData.flow.detected_protocol || 0,
        detection_guessed: flowData.flow.detection_guessed ? 1 : 0,
        dns_host_name: flowData.flow.dns_host_name || '',
        host_server_name: flowData.flow.host_server_name || '',
        digest: flowData.flow.digest || ''
      },
      meta: {
        local_mac: flowData.flow.local_mac
      }
    };
  }
}

module.exports = NetifyFlowProcessor;
