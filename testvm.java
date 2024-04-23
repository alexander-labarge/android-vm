package com.labarge.ig88vm;

import android.app.Activity;
import android.content.Context;
import android.os.Bundle;
import android.system.virtualmachine.VirtualMachine;
import android.system.virtualmachine.VirtualMachineCallback;
import android.system.virtualmachine.VirtualMachineConfig;
import android.system.virtualmachine.VirtualMachineManager;
import java.util.concurrent.Executors;

public class MainActivity extends Activity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // Get VirtualMachineManager system service
        VirtualMachineManager vmm = getSystemService(VirtualMachineManager.class);
        if (vmm == null) {
            // AVF is not supported on this device
            return;
        }

        // Create VM configuration
        VirtualMachineConfig config = new VirtualMachineConfig.Builder(this)
                .setProtectedVm(true)
                .setPayloadBinaryName("my_payload.so")
                .build();

        // Attempt to get or create a virtual machine instance
        VirtualMachine vm = vmm.getOrCreate("my vm", config);

        // Register a callback to handle VM events
        vm.setCallback(Executors.newSingleThreadExecutor(), new VirtualMachineCallback() {
            @Override
            public void onPayloadStarted() {
                // Called when VM payload starts
            }

            @Override
            public void onPayloadReady() {
                // Called when VM payload is ready to accept connections
            }

            @Override
            public void onPayloadFinished(int exitCode) {
                // Called when VM payload has exited normally
            }

            @Override
            public void onError(int errorCode, String errorMessage) {
                // Called if an error occurs
            }

            @Override
            public void onStopped(int reasonCode) {
                // Called when VM is no longer running
            }
        });

        // Run the virtual machine
        vm.run();
    }
}