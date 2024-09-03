//
//  ViewController.swift
//  bleTest
//
//  Created by Jason Sobotka on 11/11/23.
//

import UIKit
import CoreBluetooth
import os

class ViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    private var centralManager: CBCentralManager!
    
    private var discoveredPeripherals = [CBPeripheral]()
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    
    private var originalContentOffset: CGPoint?
    
    private var rssiUpdateTimer: Timer?

    
    @IBOutlet weak var bleTableView: UITableView!
    
    @IBOutlet weak var bleConnect: UIButton!
    
    @IBOutlet weak var bleDisconnect: UIButton!
    
    @IBOutlet weak var bleSendMsg: UIButton!
    
    @IBOutlet weak var bleTextField: UITextField!
    
    @IBOutlet weak var scrollView: UIScrollView!

    @IBOutlet weak var bleSignalStr: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        bleSendMsg.isEnabled = false
        bleDisconnect.isEnabled = false
        
        centralManager = CBCentralManager(delegate: self, queue: nil)
        bleTableView.delegate = self
        bleTableView.dataSource = self
        bleTableView.register(UITableViewCell.self, forCellReuseIdentifier: "DeviceCell")
        
        // Add keyboard observers
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    func startScan() {
        centralManager.scanForPeripherals(withServices: nil, options: nil)
    }
    
    func connect(peripheral: CBPeripheral) {
        centralManager.connect(peripheral, options: nil)
        bleSendMsg.isEnabled = true
    }
    
    func disconnect(peripheral: CBPeripheral) {
        centralManager.cancelPeripheralConnection(peripheral)
    }
    
    func reportState(state: CBManagerState) {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "State Report")
        var stateStr = ""
        switch state {
        case .poweredOn:
            stateStr = "poweredOn"
        case .poweredOff:
            stateStr = "poweredOff"
        case .resetting:
            stateStr = "resetting"
        case .unsupported:
            stateStr = "unsupported"
        case .unauthorized:
            stateStr = "unauthorized"
        case .unknown:
            stateStr = "unknown"
        default:
            stateStr = "badState"
        }
        logger.log("CBDelegate handled state \(stateStr)")
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return discoveredPeripherals.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "DeviceCell", for: indexPath)
        let peripheral = discoveredPeripherals[indexPath.row]
        cell.textLabel?.text = peripheral.name ?? "Unknown Device"
        
        if peripheral == connectedPeripheral {
            cell.accessoryType = .checkmark
            cell.textLabel?.textColor = .green
        } else {
            cell.accessoryType = .none
            cell.textLabel?.textColor = .black
        }
        
        return cell
    }
    
    @IBAction func sendButtonTapped(_ sender: UIButton) {
        guard let text = bleTextField.text, !text.isEmpty else {
                   print("Text field is empty")
                   return
               }
               
        sendTextToBLEDevice(text)
        bleTextField.resignFirstResponder()
    }
    // MARK: - UITableViewDelegate
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    //    let peripheral = discoveredPeripherals[indexPath.row]
    //    connect(peripheral: peripheral)
    }
    
     deinit {
         // Remove observers when the view controller is deallocated
         NotificationCenter.default.removeObserver(self)
         
         stopMonitoringRSSI()
     }

    @objc func keyboardWillShow(notification: NSNotification) {
        guard let keyboardSize = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue,
              let activeField = findFirstResponder(in: view) as? UITextField else {
            return
        }

        // Store the original content offset
        originalContentOffset = scrollView.contentOffset

        let bottomOfTextField = activeField.convert(activeField.bounds, to: scrollView).maxY
        let topOfKeyboard = scrollView.frame.height - keyboardSize.height

        // Calculate the distance we need to scroll
        let distanceToScroll = bottomOfTextField - topOfKeyboard + 20 // Add some padding

        if distanceToScroll > 0 {
            let contentOffset = CGPoint(x: 0, y: scrollView.contentOffset.y + distanceToScroll)
            UIView.animate(withDuration: 0.3) {
                self.scrollView.setContentOffset(contentOffset, animated: false)
            }
        }
    }

    @objc func keyboardWillHide(notification: NSNotification) {
        // Restore the original content offset
         if let originalOffset = originalContentOffset {
             UIView.animate(withDuration: 0.3) {
                 self.scrollView.setContentOffset(originalOffset, animated: false)
             }
         }
         originalContentOffset = nil
    }

     func findFirstResponder(in view: UIView) -> UIView? {
         if view.isFirstResponder {
             return view
         }
         for subview in view.subviews {
             if let firstResponder = findFirstResponder(in: subview) {
                 return firstResponder
             }
         }
         return nil
     }
    
    func startMonitoringRSSI() {
        rssiUpdateTimer?.invalidate()
        
        rssiUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
            [weak self] _ in
            self?.updateRSSI()
        }
    }
    
    func stopMonitoringRSSI() {
        rssiUpdateTimer?.invalidate()
        rssiUpdateTimer = nil
    }
    
    private func updateRSSI() {
        guard let peripheral = connectedPeripheral else {
            print("No connected peripheral")
            return
        }
        
        peripheral.readRSSI()
    }
}

extension ViewController: CBCentralManagerDelegate {
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "BLE Delegate")
        switch central.state {
        case .poweredOn:
            startScan()
        case .poweredOff:
            reportState(state: .poweredOff)
        case .resetting:
            reportState(state: .resetting)
        case .unauthorized:
            reportState(state: .unauthorized)
        case .unsupported:
            reportState(state: .unsupported)
        case .unknown:
            reportState(state: .unknown)
        default:
            logger.log("Unhandled state")
        }
    }
    
    // In CBCentralManagerDelegate class/extension
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if !discoveredPeripherals.contains(peripheral) {
            discoveredPeripherals.append(peripheral)
            DispatchQueue.main.async {
                self.bleTableView.reloadData()
            }
        }
    }
    
    // In CBCentralManagerDelegate class/extension
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        peripheral.delegate = self
        peripheral.discoverServices(nil)
        
        DispatchQueue.main.async {
            self.updateUIForConnectedDevice()

            // Start monitoring RSSI when connected
            self.startMonitoringRSSI()
        }
    }
     
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        // Handle error
    }
    
    @IBAction func disconnectButtonTapped(_ sender: UIButton) {
        guard let peripheral = connectedPeripheral else {
            print("No device connected")
            return
        }
        
        centralManager.cancelPeripheralConnection(peripheral)
        bleConnect.isEnabled = true
    }
    
    @IBAction func connectButtonTapped(_ send: UIButton) {
        guard let indexPath = bleTableView.indexPathForSelectedRow else {
            print("No device selected")
            return
        }
        
        let peripheral = discoveredPeripherals[indexPath.row]
        connect(peripheral: peripheral)
        
        bleConnect.isEnabled = false
        bleDisconnect.isEnabled = true
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let error = error {
            print("Disconnection error: \(error.localizedDescription)")
        } else {
            print("Successfully disconnected from peripheral")
        }
        
        DispatchQueue.main.async {
            self.updateUIForDisconnectedDevice()
            
            // Stop monitoring RSSI when disconnected
            self.stopMonitoringRSSI()
        }
        
        connectedPeripheral = nil
        writeCharacteristic = nil
    }

    func updateUIForDisconnectedDevice() {
        bleTableView.reloadData()  // This will reset all cells to their default state
        bleConnect.isEnabled = true
        bleDisconnect.isEnabled = false
        bleSendMsg.isEnabled = false
        
        bleTextField.resignFirstResponder()
    }
    
    func updateUIForConnectedDevice() {
        bleTableView.reloadData()
        
        bleConnect.isEnabled = false
        bleDisconnect.isEnabled = true
        bleSendMsg.isEnabled = true
    }
    
    func sendTextToBLEDevice(_ text: String) {
        guard let peripheral = connectedPeripheral,
              let characteristic = writeCharacteristic else {
            print("No connected peripheral or write characteristic")
            return
        }

        guard let data = text.data(using: .utf8) else {
            print("Failed to convert text to data")
            return
        }

        peripheral.writeValue(data, for: characteristic, type: .withResponse)
        print("Sending text: \(text)")
    }
}

extension ViewController: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            if characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) {
                writeCharacteristic = characteristic
                // Enable UI for sending text
                bleSendMsg.isEnabled = true
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Error writing characteristic value: \(error.localizedDescription)")
        } else {
            print("Successfully wrote value to characteristic")
            // Clear text field or update UI as needed
            bleTextField.text = ""
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        if let error = error {
            print("Error reading RSSI: \(error.localizedDescription)")
            return
        }
        
        let rssiValue = RSSI.intValue
        DispatchQueue.main.async {
            self.bleSignalStr.text = "\(rssiValue) dBm"
        }
    }
}
