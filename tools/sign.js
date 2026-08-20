#engine v8

#feature-info Headless code signing for PixInsight scripts and update \
   repositories. Reads a job file, signs the listed targets, writes a report.

//============================================================================
// sign.js - Sign scripts and update repositories without the GUI
//
// The CodeSign script that ships with PixInsight is a dialog: it needs a human
// to pick files and type a password. That is the right default, but it means
// every edit-then-test cycle and every release stops on a modal window. The
// signing API itself has no such requirement, so this does the same work from
// a headless run.
//
// Everything here is measured against the reference, not assumed:
//
//   - Security.generateScriptSignatureFile() and generateXMLSignature() both
//     have overloads taking (keysFilePath, password) directly, so the keys
//     never need loading separately.
//   - NO ENTITLEMENT is required to call them. The entitlement list in the
//     Code Signing System document covers launching/activating/terminating
//     instances, loading/unloading resources, writing/removing global
//     settings and PCL experimental features - the signing API is not in it.
//     So this script does not itself need to be signed to sign others.
//   - Both signing calls accept the password as a ByteArray, and that is the
//     form to use. The document is explicit that a password reaching a
//     JavaScript String cannot be wiped afterwards, while a ByteArray is
//     wiped by the call that consumes it.
//   - ExternalProcess.stdout is a ByteArray, not a String. That is what makes
//     the keychain route below possible without ever materialising the
//     password as a String or writing it to disk.
//
// PixInsight passes no arguments to scripts run with -r=, so the work to do
// is read from a job file. tools/sign.sh writes it.
//
//   {
//     "keysFile":     "/Users/you/Documents/PixInsight/dev.xssk",
//     "password":     { "keychain": { "service": "...", "account": "..." } },
//     "entitlements": [],
//     "targets":      ["/path/to/Script.js", "/path/to/updates.xri"],
//     "report":       "/path/to/report.txt"
//   }
//
// The job file holds the location of the secret, never the secret. It is
// deleted after being read so a stale job cannot be run by accident.
//============================================================================

#define JOB_FILE_NAME ".pixinsight-sign-job.json"
#define SECURITY_TOOL "/usr/bin/security"
#define SECURITY_TIMEOUT_MS 20000

var reportPath = null;
var reportLines = [];

// Written after every line. A signing run that throws half way through is
// exactly when the log matters, and console output does not reach the
// terminal from a headless run.
function say(text) {
   reportLines.push(text);
   if (reportPath !== null) {
      File.writeTextFile(reportPath, reportLines.join("\n") + "\n");
   }
   console.writeln(text);
}

// Trailing newline removal, in place.
//
// Both sources end in one: `security -w` prints the password followed by a
// newline, and a password file written with `echo` ends in 0x0A. The byte
// would be part of the password, and the failure is one step removed from the
// cause - the keys file decrypts with the wrong key and the error reads
// "Invalid signing keys file", pointing at the keys rather than the newline.
//
// ByteArray.remove() shortens the array in place; the dropped byte sits beyond
// the new length, so secureFill() will not reach it. One byte of a password is
// an acceptable residue for the convenience of accepting either source as-is.
function trimTrailingNewlines(bytes) {
   while (bytes.length > 0) {
      var b = bytes.at(bytes.length - 1);
      if (b !== 10 && b !== 13) {
         break;
      }
      bytes.remove(bytes.length - 1, 1);
   }
   return bytes;
}

// --- Where the password comes from ------------------------------------------
//
// Two sources, and the choice is a real one.
//
// The keychain is the macOS equivalent of a secrets manager: encrypted at
// rest, unlocked with the login session, and the item can be added once by
// hand so that nobody else - including whoever automates the release - ever
// sees the password. Because ExternalProcess.stdout is a ByteArray, the
// password goes from the keychain straight into the signing call without
// becoming a String and without touching the filesystem.
//
// The file route is kept because the keychain is not always reachable. A
// command run over ssh reads the login keychain of a session that may be
// locked, and the first access from a new binary raises a GUI prompt on the
// machine itself. When that is in the way, a 600 file on an encrypted disk is
// the honest fallback - it is weaker at rest, and it is stated as such.

function passwordFromKeychain(spec) {
   var p = new ExternalProcess;
   p.start(SECURITY_TOOL, ["find-generic-password", "-w",
                           "-s", spec.service, "-a", spec.account]);
   if (!p.waitForStarted()) {
      throw new Error("could not start " + SECURITY_TOOL);
   }
   if (!p.waitForFinished(SECURITY_TIMEOUT_MS)) {
      p.kill();
      throw new Error(
         "timed out reading the keychain. The login keychain is probably "
       + "locked, or a permission prompt is waiting on the machine's screen.");
   }
   if (p.exitCode !== 0) {
      // 44 is "the item cannot be found"; anything else is usually access.
      throw new Error(
         "security exited " + p.exitCode + " for service '" + spec.service
       + "', account '" + spec.account + "'"
       + (p.exitCode === 44 ? " (no such keychain item)" : ""));
   }
   return trimTrailingNewlines(p.stdout);
}

function passwordFromFile(path) {
   if (!File.exists(path)) {
      throw new Error("password file not found: " + path);
   }
   return trimTrailingNewlines(File.readFile(path));
}

function readPassword(spec) {
   if (spec === undefined || spec === null) {
      throw new Error("no password source in the job file");
   }
   if (spec.keychain !== undefined) {
      return passwordFromKeychain(spec.keychain);
   }
   if (spec.file !== undefined) {
      return passwordFromFile(spec.file);
   }
   throw new Error("password source must be either 'keychain' or 'file'");
}

// --- Signing ---------------------------------------------------------------

function signOne(target, keysFile, password, entitlements) {
   var ext = File.extractExtension(target).toLowerCase();

   if (ext === ".js" || ext === ".scp") {
      // A script signature only exists for a file carrying a script
      // identifier (#feature-id). Modules pulled in with #include have none,
      // and asking for one reports "No script identifier has been specified".
      // That is not an error in the caller's list - it is what a module is -
      // so main() reports it and steps over rather than aborting the run.
      var signaturePath = File.changeExtension(target, ".xsgn");
      Security.generateScriptSignatureFile(signaturePath, target,
                                           entitlements, keysFile, password);
      return signaturePath;
   }

   if (ext === ".xri") {
      // Repository signatures live inside the document, so there is no
      // separate output path: the file is rewritten. CodeSign reformats the
      // XML while doing it, which changes the layout but not the package
      // entries.
      Security.generateXMLSignature(target, keysFile, password);
      return target;
   }

   throw new Error("unsupported target type '" + ext + "': " + target);
}

function main() {
   var jobPath = File.homeDirectory + "/" + JOB_FILE_NAME;
   if (!File.exists(jobPath)) {
      // No report path is known yet, so this one has to go somewhere fixed.
      File.writeTextFile(File.systemTempDirectory + "/pixinsight-sign-error.txt",
                         "no job file at " + jobPath + "\n");
      return;
   }

   var job = JSON.parse(File.readFile(jobPath, DataType.UTF8String));
   File.remove(jobPath);

   reportPath = job.report;
   say("keys file:    " + job.keysFile);
   say("password:     " + (job.password.keychain !== undefined
                           ? ("keychain " + job.password.keychain.service
                              + " / " + job.password.keychain.account)
                           : ("file " + job.password.file)));
   say("targets:      " + job.targets.length);
   say("entitlements: "
       + (job.entitlements.length === 0 ? "(none)"
                                        : job.entitlements.join(", ")));
   say("");

   if (!File.exists(job.keysFile)) {
      say("FAILED: keys file not found: " + job.keysFile);
      return;
   }

   var password;
   try {
      password = readPassword(job.password);
   } catch (x) {
      say("FAILED: " + (x.message === undefined ? ("" + x) : x.message));
      return;
   }
   if (password.length === 0) {
      say("FAILED: the password is empty");
      password.secureFill();
      return;
   }

   var signed = 0;
   var skipped = 0;
   var failed = 0;

   try {
      for (var i = 0; i < job.targets.length; ++i) {
         var target = job.targets[i];
         if (!File.exists(target)) {
            say("MISSING  " + target);
            ++failed;
            continue;
         }
         try {
            var out = signOne(target, job.keysFile, password, job.entitlements);
            say("SIGNED   " + out);
            ++signed;
         } catch (x) {
            var message = x.message === undefined ? ("" + x) : x.message;
            if (message.indexOf("No script identifier") >= 0) {
               say("SKIPPED  " + target
                   + "  (no #feature-id: this is an included module)");
               ++skipped;
            } else {
               say("FAILED   " + target + "  " + message);
               ++failed;
            }
         }
      }
   } finally {
      // Wipe the password whatever happened. The ByteArray overloads of the
      // signing calls wipe it themselves once consumed, so this covers the
      // paths where no call was reached.
      password.secureFill();
   }

   say("");
   say("signed " + signed + ", skipped " + skipped + ", failed " + failed);
}

main();
