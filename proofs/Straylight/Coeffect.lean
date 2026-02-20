-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                              // straylight coeffect proofs //
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
-- Coeffect types and proofs for straylight-llm gateway.
-- These types mirror gateway/src/Coeffect/Types.hs
--
-- All proofs are complete — no `sorry`, no `axiom` escapes.
--
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

namespace Straylight.Coeffect

-- ══════════════════════════════════════════════════════════════════════════════
--                                                              // hash types //
-- ══════════════════════════════════════════════════════════════════════════════

/-- A SHA256 hash represented as a 32-byte list.
    Mirrors `Hash` in Coeffect/Types.hs -/
structure Hash where
  bytes : List UInt8
  size_eq : bytes.length = 32
  deriving DecidableEq

/-- Hash equality is reflexive -/
theorem Hash.eq_refl (h : Hash) : h = h := rfl

/-- Construct a zero hash (all zeros) -/
def Hash.zero : Hash where
  bytes := List.replicate 32 0
  size_eq := by native_decide

/-- Zero hash has correct size -/
theorem Hash.zero_size : Hash.zero.bytes.length = 32 := Hash.zero.size_eq

-- ══════════════════════════════════════════════════════════════════════════════
--                                                       // cryptographic keys //
-- ══════════════════════════════════════════════════════════════════════════════

/-- Ed25519 public key (32 bytes).
    Mirrors `PublicKey` in Coeffect/Types.hs -/
structure PublicKey where
  bytes : List UInt8
  size_eq : bytes.length = 32
  deriving DecidableEq

/-- Ed25519 signature (64 bytes).
    Mirrors `Signature` in Coeffect/Types.hs -/
structure Signature where
  bytes : List UInt8
  size_eq : bytes.length = 64
  deriving DecidableEq

-- ══════════════════════════════════════════════════════════════════════════════
--                                                         // coeffect types //
-- ══════════════════════════════════════════════════════════════════════════════

/-- A coeffect: what a computation requires from the environment.
    Mirrors `Coeffect` ADT in Coeffect/Types.hs -/
inductive Coeffect where
  | pure                              -- needs nothing external
  | network                           -- needs network access
  | auth (provider : String)          -- needs credential for provider
  | sandbox (name : String)           -- needs specific sandbox
  | filesystem (path : String)        -- needs filesystem path
  | combined (cs : List Coeffect)     -- multiple requirements (tensor product)
  deriving Repr

/-- A simple coeffect (not combined) is pure only if it's the pure constructor -/
def Coeffect.isSimplePure : Coeffect -> Bool
  | .pure => true
  | _ => false

/-- Pure coeffect is pure -/
theorem Coeffect.pure_isSimplePure : Coeffect.pure.isSimplePure = true := rfl

/-- Network coeffect is not pure -/
theorem Coeffect.network_not_isSimplePure : Coeffect.network.isSimplePure = false := rfl

/-- Auth coeffect is not pure -/
theorem Coeffect.auth_not_isSimplePure (p : String) : (Coeffect.auth p).isSimplePure = false := rfl

/-- Filesystem coeffect is not pure -/
theorem Coeffect.filesystem_not_isSimplePure (p : String) : (Coeffect.filesystem p).isSimplePure = false := rfl

/-- Sandbox coeffect is not pure -/
theorem Coeffect.sandbox_not_isSimplePure (n : String) : (Coeffect.sandbox n).isSimplePure = false := rfl

-- ══════════════════════════════════════════════════════════════════════════════
--                                                        // network access //
-- ══════════════════════════════════════════════════════════════════════════════

/-- HTTP method enumeration -/
inductive HttpMethod where
  | GET | POST | PUT | DELETE | PATCH | HEAD | OPTIONS
  deriving Repr, DecidableEq

/-- Network access witness.
    Mirrors `NetworkAccess` in Coeffect/Types.hs -/
structure NetworkAccess where
  url : String
  method : HttpMethod
  contentHash : Hash
  timestamp : Nat
  deriving DecidableEq

/-- Two network accesses to the same URL are equivalent if methods match -/
def NetworkAccess.sameEndpoint (a b : NetworkAccess) : Bool :=
  a.url == b.url && a.method == b.method

/-- Same endpoint is reflexive -/
theorem NetworkAccess.sameEndpoint_refl (a : NetworkAccess) :
    a.sameEndpoint a = true := by
  simp [sameEndpoint]

-- ══════════════════════════════════════════════════════════════════════════════
--                                                      // filesystem access //
-- ══════════════════════════════════════════════════════════════════════════════

/-- Filesystem access mode -/
inductive FilesystemMode where
  | read | write | execute
  deriving Repr, DecidableEq

/-- Filesystem access witness.
    Mirrors `FilesystemAccess` in Coeffect/Types.hs -/
structure FilesystemAccess where
  path : String
  mode : FilesystemMode
  contentHash : Option Hash
  timestamp : Nat
  deriving DecidableEq

/-- Read mode is less permissive than write -/
def FilesystemMode.le : FilesystemMode -> FilesystemMode -> Bool
  | .read, _ => true
  | .execute, .read => false
  | .execute, _ => true
  | .write, .write => true
  | .write, _ => false

/-- FilesystemMode.le is reflexive -/
theorem FilesystemMode.le_refl (m : FilesystemMode) : m.le m = true := by
  cases m <;> rfl

/-- Read is the least permissive mode -/
theorem FilesystemMode.read_le_all (m : FilesystemMode) :
    FilesystemMode.read.le m = true := rfl

-- ══════════════════════════════════════════════════════════════════════════════
--                                                            // auth usage //
-- ══════════════════════════════════════════════════════════════════════════════

/-- Auth token usage witness.
    Mirrors `AuthUsage` in Coeffect/Types.hs -/
structure AuthUsage where
  provider : String
  scope : Option String
  timestamp : Nat
  deriving DecidableEq

/-- Two auth usages are for the same provider -/
def AuthUsage.sameProvider (a b : AuthUsage) : Bool :=
  a.provider == b.provider

/-- Same provider is reflexive -/
theorem AuthUsage.sameProvider_refl (a : AuthUsage) :
    a.sameProvider a = true := by
  simp [sameProvider]

-- ══════════════════════════════════════════════════════════════════════════════
--                                                       // discharge proofs //
-- ══════════════════════════════════════════════════════════════════════════════

/-- Coeffect discharge proof: evidence that coeffects were satisfied.
    Mirrors `DischargeProof` in Coeffect/Types.hs
    Note: We use a simplified version without recursive Coeffect for DecidableEq -/
structure DischargeProof where
  coeffectCount : Nat           -- Number of coeffects (simplified)
  networkAccess : List NetworkAccess
  filesystemAccess : List FilesystemAccess
  authUsage : List AuthUsage
  requestId : String
  derivationHash : Hash
  outputHashes : List (String × Hash)
  startTime : Nat
  endTime : Nat
  hasSig : Bool                 -- Whether signed (simplified)
  deriving DecidableEq

/-- A proof is pure if it has no coeffects -/
def DischargeProof.isPure (p : DischargeProof) : Bool :=
  p.coeffectCount == 0

/-- A proof is signed if it has a signature -/
def DischargeProof.isSigned (p : DischargeProof) : Bool :=
  p.hasSig

/-- A proof has valid timing if end >= start -/
def DischargeProof.hasValidTiming (p : DischargeProof) : Bool :=
  p.endTime >= p.startTime

/-- Empty proof with no coeffects is pure -/
theorem DischargeProof.empty_isPure (p : DischargeProof) (h : p.coeffectCount = 0) :
    p.isPure = true := by
  simp [isPure, h]

/-- Unsigned proof is not signed -/
theorem DischargeProof.unsigned_not_signed (p : DischargeProof) (h : p.hasSig = false) :
    p.isSigned = false := by
  simp [isSigned, h]

/-- Signed proof is signed -/
theorem DischargeProof.signed_is_signed (p : DischargeProof) (h : p.hasSig = true) :
    p.isSigned = true := by
  simp [isSigned, h]

-- ══════════════════════════════════════════════════════════════════════════════
--                                                  // coeffect discharge laws //
-- ══════════════════════════════════════════════════════════════════════════════

/-- A discharge proof is valid if it has evidence for all requirements.
    Pure proofs (no coeffects) trivially have evidence.
    Non-pure proofs have evidence if they are signed. -/
def DischargeProof.hasEvidence (proof : DischargeProof) : Bool :=
  proof.isPure || proof.hasSig

/-- Pure proofs always have evidence (vacuously) -/
theorem DischargeProof.pure_has_evidence (p : DischargeProof)
    (h : p.isPure = true) : p.hasEvidence = true := by
  simp only [DischargeProof.hasEvidence, h, Bool.true_or]

-- ══════════════════════════════════════════════════════════════════════════════
--                                               // coeffect monoid structure //
-- ══════════════════════════════════════════════════════════════════════════════

/-- Coeffect tensor product (combining requirements) -/
def Coeffect.tensor (c1 c2 : Coeffect) : Coeffect :=
  match c1, c2 with
  | .pure, c => c
  | c, .pure => c
  | .combined cs1, .combined cs2 => .combined (cs1 ++ cs2)
  | .combined cs, c => .combined (cs ++ [c])
  | c, .combined cs => .combined (c :: cs)
  | c1, c2 => .combined [c1, c2]

/-- Pure is left identity for tensor -/
theorem Coeffect.tensor_pure_left (c : Coeffect) : Coeffect.pure.tensor c = c := rfl

/-- Pure is right identity for tensor -/
theorem Coeffect.tensor_pure_right (c : Coeffect) : c.tensor Coeffect.pure = c := by
  cases c <;> rfl

/-- Count non-pure simple coeffects -/
def Coeffect.countSimple : Coeffect -> Nat
  | .pure => 0
  | .network => 1
  | .auth _ => 1
  | .sandbox _ => 1
  | .filesystem _ => 1
  | .combined cs => cs.length  -- Simplified: count list length

/-- Pure has zero count -/
theorem Coeffect.pure_countSimple : Coeffect.pure.countSimple = 0 := rfl

/-- Network has one count -/
theorem Coeffect.network_countSimple : Coeffect.network.countSimple = 1 := rfl

-- ══════════════════════════════════════════════════════════════════════════════
--                                                      // proof construction //
-- ══════════════════════════════════════════════════════════════════════════════

/-- Construct an empty discharge proof -/
def DischargeProof.empty (requestId : String) (derivationHash : Hash)
    (startTime endTime : Nat) : DischargeProof where
  coeffectCount := 0
  networkAccess := []
  filesystemAccess := []
  authUsage := []
  requestId := requestId
  derivationHash := derivationHash
  outputHashes := []
  startTime := startTime
  endTime := endTime
  hasSig := false

/-- Empty discharge proof is pure -/
theorem DischargeProof.empty_isPure' (requestId : String) (derivationHash : Hash)
    (startTime endTime : Nat) :
    (DischargeProof.empty requestId derivationHash startTime endTime).isPure = true := by
  simp [empty, isPure]

/-- Empty discharge proof is unsigned -/
theorem DischargeProof.empty_unsigned (requestId : String) (derivationHash : Hash)
    (startTime endTime : Nat) :
    (DischargeProof.empty requestId derivationHash startTime endTime).isSigned = false := by
  simp [empty, isSigned]

/-- Empty discharge proof has evidence -/
theorem DischargeProof.empty_has_evidence (requestId : String) (derivationHash : Hash)
    (startTime endTime : Nat) :
    (DischargeProof.empty requestId derivationHash startTime endTime).hasEvidence = true := rfl

end Straylight.Coeffect
