/*
 * SPDX-License-Identifier: Apache-2.0
 */

package org.lineageos.ovaltine.preinstall;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageInstaller;
import android.util.Log;

public class InstallResultReceiver extends BroadcastReceiver {
    private static final String TAG = "OvaltinePreinstall";

    @Override
    public void onReceive(Context context, Intent intent) {
        final int status = intent.getIntExtra(
                PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE);
        final String msg = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE);

        if (status == PackageInstaller.STATUS_SUCCESS
                || status == PackageInstaller.STATUS_FAILURE_CONFLICT) {
            final Context appCtx = context.getApplicationContext();
            final SharedPreferences prefs =
                    appCtx.getSharedPreferences(BootReceiver.PREFS_NAME, Context.MODE_PRIVATE);
            prefs.edit().putBoolean(BootReceiver.KEY_APERTURE_DONE, true).apply();
            BootReceiver.disableSelf(appCtx);
            Log.i(TAG, "Aperture preinstall complete (status=" + status + ")");
        } else {
            Log.e(TAG, "Aperture preinstall failed (status=" + status + "): " + msg);
        }
    }
}
