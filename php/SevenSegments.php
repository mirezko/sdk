<?php

interface _7S_Transport {
    public function postAndForget($url, $payload);
    public function post($url, $payload);
}

class _7S_Base {
    private $_debug;
    public function __construct($debug = false) {
        $this->_debug = $debug;
    }
    protected function debug($msg, $obj=null) {
        if (!$this->_debug) return;
        echo $msg . "\n";
        if ($obj !== null) {
            print_r($obj);
            echo "\n";
        }
    }
}

class _7S_ModCurlTransport extends _7S_Base implements _7S_Transport {

    public function __construct($debug = false) {
        parent::__construct($debug);
        if (!function_exists('curl_init')) {
            throw new Exception('php curl module not available');
        }
    }

    public function postAndForget($url, $payload) {
        $this->post($url, $payload);
    }

    public function post($url, $payload) {
        $this->debug('url', $url);
        $ch = curl_init($url);
        if ($ch === false) {
            return false;
            $this->debug('Failed to init curl handle');
        }
        $payload = json_encode($payload);
        $this->debug('payload', $payload);
        $headers = array('Content-Type:application/json');
        if (curl_setopt($ch, CURLOPT_POSTFIELDS, $payload) === false) {
            $this->debug('failed setting payload');
            curl_close($ch);
            return false;
        }
        if (curl_setopt($ch, CURLOPT_HTTPHEADER, $headers) === false) {
            $this->debug('failed setting headers');
            curl_close($ch);
            return false;
        }
        if (curl_setopt($ch, CURLOPT_RETURNTRANSFER, true ) === false) {
            $this->debug('failed setting returntransfer');
            curl_close($ch);
            return false;
        }
        $result = curl_exec($ch);
        curl_close($ch);
        return $result;
    }

}

class _7S_SocketTransport extends _7S_Base implements _7S_Transport {

    private function postRequest($url, $payload) {
        $payload = json_encode($payload);

        $parsed_url = parse_url($url);

        print_r($parsed_url);

        if (isset($parsed_url['scheme']) && $parsed_url['scheme'] == 'https') {
            $scheme = 'https';
        }
        else {
            $scheme = 'http';
        }

        $host = $parsed_url['host'];
        if (isset($parsed_url['port'])) {
            $port = $parsed_url['port'];
        }
        else {
            if ($scheme == 'https') {
                $port = 443;
            }
            else {
                $port = 80;
            }
        }
        $path = $parsed_url['path'];

        $sock = pfsockopen(($scheme == 'https'?'ssl://':'') + $host, $port,
            $errno, $errstr, 3);
        if ($sock === false) return false;

        $req  = 'POST ' . $path . ' HTTP/1.1' . "\r\n";
        $req .= 'Host: ' . $host . "\r\n";
        $req .= 'Content-Type: application/json' . "\r\n";
        $req .= 'Content-Length: ' . strlen($payload) . "\r\n";
        $req .= "\r\n\r\n";
        $req .= $payload;

        $len = strlen($req);
        $written = 0;
        while ($written < $len) {
            $w = fwrite($sock, $req);
            if ($w === false) {
                fclose($sock);
                return false;
            }
            $written += $w;
        }

        return $sock;
    }

    public function postAndForget($url, $payload) {
        $sock = $this->postRequest($url, $payload);
        fclose($sock);
    }

    public function post($url, $payload) {
        $sock = $this->postRequest($url, $payload);

        $resp = fgets($sock, 1024);
        if (len($resp) <= 3) {
            fclose($sock);
            return false;
        }

        // TODO

        fclose($sock);
    }

}

class SevenSegments {

    const DEFAULT_TARGET = 'http://api.7segments.com';

    private $transport = null;
    private $target = SevenSegments::DEFAULT_TARGET;
    private $token = null;
    private $customer = array();
    private $project = 'default';
    private $debug = false;

    /**
     *
     * @param $token string your API token
     * @param $customer 
     */
    public function __construct($token, $customer=null, $project=null, $target=null, _7S_Transport $transport=null, $debug=false) {
        if (!is_string($token)) {
            throw new Exception('API token must be string');
        }
        $this->token = $token;
        $this->setCustomer($customer);
        if ($project !== null) {
            $this->project($project);
        }
        if ($target !== null) {
            if (!is_string($target)) {
                throw new Exception('Target must be string or not specified');
            }
            $this->target = $target;
        }
        if ($transport === null) {
            $transport = new _7S_ModCurlTransport($debug);
        }
        $this->transport = $transport;
        $this->debug = $debug;
    }

    private function setCustomer($customer=null) {
        if ($customer === null) {
            $this->customer = array();
        }
        else if (is_string($customer)) {
            $this->customer = array('registered' => $customer);
        }
        else if (is_array($customer)) {
            $this->customer = $customer;
        }
        else {
            throw new Exception('Customer must be either string or array');
        }
    }

    protected function url($path) {
        return $this->target . $path;
    }

    protected function convertMapping($val) {
        if ($val === null || count($val) == 0) {
            return new stdClass;
        }
        return $val;
    }

    public function project($project) {
        if (!is_string($project)) {
            throw new Exception('Project name must be string or not specified');
        }
        $this->project = $project;
    }

    public function track($event_type, $properties=null) {
        if (!is_string($event_type)) {
            throw new Exception('Event type must be string');
        }
        $properties = $this->convertMapping($properties);
        $event = array(
            'project_id' => $this->project,
            'customer_ids' => $this->customer,
            'company_id' => $this->token,
            'type' => $event_type,
            'properties' => $properties
        );
        $this->postAndForget('/crm/events', $event);
    }

    public function identify($customer=null, $properties=null) {
        $this->setCustomer($customer);
        $properties = $this->convertMapping($properties);
        $this->update($properties);
    }

    public function update($properties) {
        $properties = $this->convertMapping($properties);
        $data = array(
            'ids' => $this->customer,
            'company_id' => $this->token,
            'properties' => $properties
        );
        $this->postAndForget('/crm/customers', $data);
    }

    public function evaluate($campaigns=null, $customer_properties=null) {
        if ($campaigns === null) {
            $campaigns = array();
        }
        $customer_properties = $this->convertMapping($customer_properties);
        $data = array(
            'campaigns' => $campaigns,
            'ids' => $this->customer,
            'company_id' => $this->token,
            'properties' => $customer_properties
        );
        $response = $this->post('/campaigns/automated/evaluate', $data);
        if (count($campaigns) == 1) {
            return $response['data'][0];
        }
        else {
            return $response;
        }
    }

    private function post($path, $payload) {
        return $this->transport->post($this->url($path), $payload);
    }

    private function postAndForget($path, $payload) {
        return $this->transport->postAndForget($this->url($path), $payload);
    }

}

