import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Scanner',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const BleScanner(),
    );
  }
}

class BleScanner extends StatefulWidget {
  const BleScanner({Key? key}) : super(key: key);

  @override
  _BleScannerState createState() => _BleScannerState();
}

class _BleScannerState extends State<BleScanner> {
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  StreamSubscription? _scanStream;
  StreamSubscription? _connectionStream;
  final List<DiscoveredDevice> _devices = [];
  final Set<String> _deviceIds = {};
  bool _isScanning = false;
  bool _isConnected = false;
  DiscoveredDevice? _selectedDevice;

  // Replace these with your actual UUIDs
  final serviceUuid = Uuid.parse('12345678-1234-1234-1234-123456789abc');
  final characteristicUuid = Uuid.parse('87654321-4321-4321-4321-abc123456789');

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    // Request all necessary permissions for BLE
    final permissions = await Future.wait([
      Permission.locationWhenInUse.request(),
      Permission.bluetoothScan.request(),
      Permission.bluetoothConnect.request(),
    ]);

    if (permissions.every((status) => status.isGranted)) {
      debugPrint('All permissions granted');
    } else {
      _showPermissionDeniedDialog();
    }
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permissions Required'),
        content: const Text(
          'BLE scanning requires location and bluetooth permissions. '
              'Please grant these permissions in your device settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _startScan() {
    setState(() {
      _isScanning = true;
      _devices.clear();
      _deviceIds.clear();
    });

    _scanStream = _ble.scanForDevices(
      withServices: [],
      scanMode: ScanMode.balanced,
    ).listen(
          (device) {
        if (!_deviceIds.contains(device.id)) {
          setState(() {
            _deviceIds.add(device.id);
            _devices.add(device);
          });
        }
      },
      onError: (error) {
        debugPrint('Scanning error: $error');
        _showErrorDialog('Scanning error', error.toString());
      },
    );

    // Auto-stop scan after 30 seconds
    Future.delayed(const Duration(seconds: 30), () {
      if (_isScanning) {
        _stopScan();
      }
    });
  }

  void _stopScan() {
    _scanStream?.cancel();
    setState(() {
      _isScanning = false;
    });
  }

  Future<void> _connectToDevice(DiscoveredDevice device) async {
    try {
      setState(() {
        _isScanning = false;
        _selectedDevice = device;
      });

      _stopScan();

      _connectionStream = _ble.connectToDevice(
        id: device.id,
        connectionTimeout: const Duration(seconds: 10),
      ).listen(
            (connectionState) {
          debugPrint('Connection state: ${connectionState.connectionState}');
          setState(() {
            _isConnected = connectionState.connectionState == DeviceConnectionState.connected;
          });
        },
        onError: (error) {
          debugPrint('Connection error: $error');
          _showErrorDialog('Connection error', error.toString());
        },
      );
    } catch (e) {
      debugPrint('Error connecting to device: $e');
      _showErrorDialog('Connection error', e.toString());
    }
  }

  void _disconnect() {
    _connectionStream?.cancel();
    setState(() {
      _isConnected = false;
      _selectedDevice = null;
    });
  }

  Future<void> _readCharacteristic() async {
    if (_selectedDevice == null || !_isConnected) {
      _showErrorDialog('Error', 'No device connected');
      return;
    }

    try {
      final characteristic = QualifiedCharacteristic(
        serviceId: serviceUuid,
        characteristicId: characteristicUuid,
        deviceId: _selectedDevice!.id,
      );

      final response = await _ble.readCharacteristic(characteristic);
      _showSuccessDialog('Read Value', 'Value: ${response.toString()}');
    } catch (e) {
      debugPrint('Error reading characteristic: $e');
      _showErrorDialog('Read error', e.toString());
    }
  }

  Future<void> _writeCharacteristic(List<int> value) async {
    if (_selectedDevice == null || !_isConnected) {
      _showErrorDialog('Error', 'No device connected');
      return;
    }

    try {
      final characteristic = QualifiedCharacteristic(
        serviceId: serviceUuid,
        characteristicId: characteristicUuid,
        deviceId: _selectedDevice!.id,
      );

      await _ble.writeCharacteristicWithResponse(characteristic, value: value);
      _showSuccessDialog('Success', 'Value written successfully');
    } catch (e) {
      debugPrint('Error writing characteristic: $e');
      _showErrorDialog('Write error', e.toString());
    }
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scanStream?.cancel();
    _connectionStream?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Scanner'),
        actions: [
          if (_isScanning)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _isScanning ? _stopScan : _startScan,
                  icon: Icon(_isScanning ? Icons.stop : Icons.search),
                  label: Text(_isScanning ? 'Stop Scan' : 'Start Scan'),
                ),
                if (_isConnected) ...[
                  ElevatedButton.icon(
                    onPressed: _disconnect,
                    icon: const Icon(Icons.bluetooth_disabled),
                    label: const Text('Disconnect'),
                  ),
                ],
              ],
            ),
          ),
          if (_isConnected) ...[
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: _readCharacteristic,
                    icon: const Icon(Icons.download),
                    label: const Text('Read'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _writeCharacteristic([0x01, 0x02, 0x03]),
                    icon: const Icon(Icons.upload),
                    label: const Text('Write'),
                  ),
                ],
              ),
            ),
          ],
          Expanded(
            child: ListView.builder(
              itemCount: _devices.length,
              itemBuilder: (context, index) {
                final device = _devices[index];
                final isSelected = device.id == _selectedDevice?.id;

                return Card(
                  color: isSelected ? Colors.blue.shade100 : null,
                  child: ListTile(
                    leading: const Icon(Icons.bluetooth),
                    title: Text(
                      device.name.isNotEmpty ? device.name : 'Unknown Device',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'ID: ${device.id}\nRSSI: ${device.rssi} dBm',
                    ),
                    trailing: Icon(
                      isSelected ? Icons.bluetooth_connected : Icons.bluetooth,
                      color: isSelected ? Colors.blue : null,
                    ),
                    onTap: () => _connectToDevice(device),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}