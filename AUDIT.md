Senior Web3 Auditor & Red Team Review

Overall security posture: Adequate

Mission: Execute a zero-fluff, evidence-based security audit. Prioritize user fund safety, invariant preservation, and auditability.

Findings

Title: Module/validator removals are O(n); worst-case gas DoS risk
Severity: Low
Impact: Account configuration updates (remove module/validator) can become prohibitively expensive with large sets
Likelihood: Low→Medium (usage dependent)
Evidence: `src/modules/ModuleManager.sol:26-37` uses a for-loop + swap-pop in `_removeModule`; `src/validators/ValidatorManager.sol:_removeValidator` uses similar pattern.

POC:
// Add many modules; removal becomes expensive (illustrative)
// for (uint256 i = 0; i < 1000; i++) account.addModule(address(new M()));
// account.removeModule(firstAdded); // may approach L1 block gas in worst case

Fix:
diff
--- a/src/modules/ModuleManager.sol
+++ b/src/modules/ModuleManager.sol
@@
-abstract contract ModuleManager {
-    mapping(address => bool) internal _modules;
-    address[] internal _moduleList;
+abstract contract ModuleManager {
+    mapping(address => bool) internal _modules;
+    address[] internal _moduleList;
+    mapping(address => uint256) internal _moduleIndex;
@@
-    function _addModule(address module) internal {
+    function _addModule(address module) internal {
         if (module == address(0)) revert InvalidModule();
         if (_modules[module]) revert ModuleAlreadyAdded();
         _modules[module] = true;
-        _moduleList.push(module);
+        _moduleIndex[module] = _moduleList.length;
+        _moduleList.push(module);
         emit ModuleAdded(module);
     }
@@
-    function _removeModule(address module) internal {
+    function _removeModule(address module) internal {
         if (!_modules[module]) revert ModuleNotFound();
         delete _modules[module];
-        for (uint256 i = 0; i < _moduleList.length; i++) {
-            if (_moduleList[i] == module) {
-                _moduleList[i] = _moduleList[_moduleList.length - 1];
-                _moduleList.pop();
-                break;
-            }
-        }
+        uint256 idx = _moduleIndex[module];
+        uint256 last = _moduleList.length - 1;
+        if (idx != last) {
+            address moved = _moduleList[last];
+            _moduleList[idx] = moved;
+            _moduleIndex[moved] = idx;
+        }
+        _moduleList.pop();
+        delete _moduleIndex[module];
         emit ModuleRemoved(module);
     }

Tests Required: test_addRemoveModule_O1Removal, fuzz_manyModules_NoGasDoS
References: SWC-128

---

Title: Timestamp reliance at edges (expiry/timelock) may be miner-skew sensitive
Severity: Low
Impact: Decisions near boundary can flip within ~±15s; UX/regression flakiness
Likelihood: Low
Evidence: `src/validators/SessionKeyValidator.sol:32,54` and `src/modules/SocialRecoveryModule.sol:112,246` compare directly to `block.timestamp`.

POC:
// Warp to boundary; observe accept/reject around expiry or delay

Fix:
// Option A (code): add small buffer on grant; leave timelocks as-is
diff
--- a/src/validators/SessionKeyValidator.sol
+++ b/src/validators/SessionKeyValidator.sol
@@
-        require(expiry > block.timestamp, "past expiry");
+        require(expiry > block.timestamp + 60, "expiry too soon");

Tests Required: test_grantSessionKey_RejectsNearExpiry, test_recoveryTimelock_BufferedEdges
References: SWC-116

---

Title: postExecute result ignored; silent module failures reduce auditability
Severity: Informational
Impact: Missed detection of module post-hook failures
Likelihood: Medium
Evidence: `src/SmartAccount.sol:141-144` ignores the boolean return from `postExecute`.

POC:
// A module returns false; no revert and no event emitted → operator unaware

Fix:
diff
--- a/src/SmartAccount.sol
+++ b/src/SmartAccount.sol
@@
-        for (uint256 i2 = 0; i2 < list.length; i2++) {
-            IModule(list[i2]).postExecute(msg.sender, target, value, data, res);
-        }
+        for (uint256 i2 = 0; i2 < list.length; i2++) {
+            bool okPost = IModule(list[i2]).postExecute(msg.sender, target, value, data, res);
+            if (!okPost) {
+                // consider emitting ModulePostExecuteFailed(list[i2]) for observability
+            }
+        }

Tests Required: test_postExecute_FailureObservable, fuzz_postExecute_NoSilentFailure
References: Auditability & Event Coverage

---

Title: Freeze guardian configuration during active recovery (hardening)
Severity: Medium
Impact: Compromised owner could grief/alter recovery parameters mid-process
Likelihood: Low→Medium
Evidence: `src/modules/SocialRecoveryModule.sol` allows guardian/threshold changes during an active recovery (no guard against `activeRecovery.timestamp > 0 && !executed && !cancelled`).

POC:
// Start recovery; owner changes guardians/thresholds to make execution impractical

Fix:
diff
--- a/src/modules/SocialRecoveryModule.sol
+++ b/src/modules/SocialRecoveryModule.sol
@@
+    modifier noActiveRecovery() {
+        require(
+            activeRecovery.timestamp == 0 || activeRecovery.executed || activeRecovery.cancelled,
+            "Recovery active"
+        );
+        _;
+    }
@@
-    function proposeGuardian(address guardian) external onlyAccount {
+    function proposeGuardian(address guardian) external onlyAccount noActiveRecovery {
@@
-    function addGuardian(address guardian) external onlyAccount {
+    function addGuardian(address guardian) external onlyAccount noActiveRecovery {
@@
-    function removeGuardian(address guardian) external onlyAccount {
+    function removeGuardian(address guardian) external onlyAccount noActiveRecovery {
@@
-    function setThreshold(uint256 _threshold) external onlyAccount {
+    function setThreshold(uint256 _threshold) external onlyAccount noActiveRecovery {

Tests Required: test_noConfigDuringActiveRecovery, fuzz_recoveryFlow_ConfigFrozen
References: Config Safety

---

Informational (design)
- ETH spending limits are not enforced by `SpendingLimitModule` (module evaluates ERC20 selectors; ETH outflow would require value-aware policy). If desired, add a policy path that inspects `value` in `SmartAccount.execute` or a dedicated ETH limit module.

Executive Summary
- Findings by severity: Medium 1 (hardening), Low 2, Informational 2 (inc. design note)
- Top risks: Configuration DoS (O(n) removal) in extreme usage; reduced observability of module failures; potential griefing during recovery without freeze
- Launch blockers: None at Critical/High level; do not bless until CI coverage + slither pass and tests for the above are merged

Remediation Plan
1) Add O(1) removal indices in `ModuleManager` (Low complexity)
2) Add 60s buffer on session key grant boundary (Low complexity) or document explicitly
3) Emit or handle `postExecute` failures (Low complexity)
4) Add `noActiveRecovery` guard to freeze config during recovery (Medium complexity)

Assurance Matrix
Invariant                         Test Proof
No config change during recovery  test_noConfigDuringActiveRecovery
Module removal O(1)               test_addRemoveModule_O1Removal
Expiry insensitive to ±15s skew   test_grantSessionKey_RejectsNearExpiry
Post-hook failures observable     test_postExecute_FailureObservable

Do Not Bless
- Never mark audit-ready until: All Critical/High closed (done), CI runs `slither . --exclude-informational` and `forge coverage` successfully, and the tests listed above are added.