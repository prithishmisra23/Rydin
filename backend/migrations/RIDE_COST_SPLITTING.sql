-- ================================================================
-- RIDE COST SPLITTING PLATFORM DATABASE SCHEMA
-- Support for Uber, Ola, Rapido, and other ride services
-- ================================================================

-- 1. ID Verifications table
CREATE TABLE IF NOT EXISTS id_verifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES profiles(id) ON DELETE CASCADE,
  id_image_url TEXT NOT NULL,
  extracted_name TEXT,
  extracted_id_number TEXT,
  college_name TEXT,
  verified_at TIMESTAMP,
  verification_status TEXT DEFAULT 'verified' CHECK (verification_status IN ('pending', 'verified', 'rejected')),
  is_valid BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT NOW()
);

-- 2. Ride Links table (parsed from Uber/Ola/Rapido)
CREATE TABLE IF NOT EXISTS ride_links (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  platform TEXT NOT NULL,  -- 'uber', 'ola', 'rapido', 'other'
  original_link TEXT NOT NULL,
  pickup_location TEXT NOT NULL,
  dropoff_location TEXT NOT NULL,
  ride_type TEXT,  -- 'UberX', 'Uber Prime', 'Ola', 'Rapido', etc.
  base_price DECIMAL(10, 2),
  total_price DECIMAL(10, 2) NOT NULL,
  currency TEXT DEFAULT 'INR',
  estimated_duration INT,  -- in minutes
  estimated_distance DECIMAL(8, 2),  -- in km
  raw_metadata JSONB,  -- Store full extracted data
  extracted_at TIMESTAMP DEFAULT NOW(),
  created_at TIMESTAMP DEFAULT NOW()
);

-- 3. Cost Splits table (shared rides)
CREATE TABLE IF NOT EXISTS cost_splits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_by UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  ride_link_id UUID REFERENCES ride_links(id) ON DELETE SET NULL,
  title TEXT,  -- "Airport ride", "Mall trip with friends", etc.
  total_amount DECIMAL(10, 2) NOT NULL,
  split_count INT DEFAULT 1,
  amount_per_person DECIMAL(10, 2),
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'settled', 'expired', 'cancelled')),
  share_token VARCHAR(32) NOT NULL UNIQUE,  -- For shareable link
  description TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  expires_at TIMESTAMP DEFAULT (NOW() + INTERVAL '24 hours')
);

-- 4. Split Members table (people in the cost split)
CREATE TABLE IF NOT EXISTS split_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  split_id UUID NOT NULL REFERENCES cost_splits(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  amount_owed DECIMAL(10, 2) NOT NULL,
  amount_paid DECIMAL(10, 2) DEFAULT 0,
  payment_status TEXT DEFAULT 'pending' CHECK (payment_status IN ('pending', 'paid', 'settled')),
  joined_at TIMESTAMP DEFAULT NOW(),
  settled_at TIMESTAMP,
  UNIQUE(split_id, user_id)
);

-- 5. Settlement Transactions (payment tracking)
CREATE TABLE IF NOT EXISTS settlements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  payer_id UUID NOT NULL REFERENCES profiles(id),
  payee_id UUID NOT NULL REFERENCES profiles(id),
  amount DECIMAL(10, 2) NOT NULL,
  split_id UUID REFERENCES cost_splits(id),
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'disputed')),
  proof_url TEXT,  -- UPI screenshot, receipt, etc.
  payment_method TEXT,  -- 'upi', 'bank_transfer', 'cash', etc.
  created_at TIMESTAMP DEFAULT NOW(),
  completed_at TIMESTAMP
);

-- ================================================================
-- RLS POLICIES
-- ================================================================

-- Enable RLS
ALTER TABLE id_verifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE ride_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE cost_splits ENABLE ROW LEVEL SECURITY;
ALTER TABLE split_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE settlements ENABLE ROW LEVEL SECURITY;

-- ID Verifications policies
DROP POLICY IF EXISTS "Users can view their own verification" ON id_verifications;
DROP POLICY IF EXISTS "Users can create/update their verification" ON id_verifications;

CREATE POLICY "Users can view their own verification"
ON id_verifications FOR SELECT
USING (auth.uid() = user_id OR auth.uid() IN (
  SELECT user_id FROM split_members 
  WHERE split_id IN (SELECT id FROM cost_splits WHERE created_by = id_verifications.user_id)
));

CREATE POLICY "Users can create/update their verification"
ON id_verifications FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own verification"
ON id_verifications FOR UPDATE USING (auth.uid() = user_id);

-- Ride Links policies
DROP POLICY IF EXISTS "Users can view their own ride links" ON ride_links;
DROP POLICY IF EXISTS "Users can create ride links" ON ride_links;

CREATE POLICY "Users can view their own ride links"
ON ride_links FOR SELECT
USING (auth.uid() = user_id OR auth.uid() IN (
  SELECT user_id FROM split_members 
  WHERE split_id IN (SELECT id FROM cost_splits WHERE ride_link_id = ride_links.id)
));

CREATE POLICY "Users can create ride links"
ON ride_links FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Cost Splits policies
DROP POLICY IF EXISTS "Users can view splits they created" ON cost_splits;
DROP POLICY IF EXISTS "Users can view splits they joined" ON cost_splits;
DROP POLICY IF EXISTS "Users can create splits" ON cost_splits;

CREATE POLICY "Users can view splits they created"
ON cost_splits FOR SELECT
USING (auth.uid() = created_by);

CREATE POLICY "Users can view splits they joined"
ON cost_splits FOR SELECT
USING (auth.uid() IN (SELECT user_id FROM split_members WHERE split_id = id));

CREATE POLICY "Users can create splits"
ON cost_splits FOR INSERT WITH CHECK (auth.uid() = created_by);

CREATE POLICY "Creator can update their splits"
ON cost_splits FOR UPDATE USING (auth.uid() = created_by)
WITH CHECK (auth.uid() = created_by);

-- Split Members policies
DROP POLICY IF EXISTS "Users can view split members" ON split_members;
DROP POLICY IF EXISTS "Users can join splits" ON split_members;

CREATE POLICY "Users can view split members"
ON split_members FOR SELECT
USING (auth.uid() IN (
  SELECT user_id FROM split_members sm2 WHERE sm2.split_id = split_id
) OR auth.uid() IN (
  SELECT created_by FROM cost_splits WHERE id = split_id
));

CREATE POLICY "Users can join splits"
ON split_members FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their membership"
ON split_members FOR UPDATE USING (auth.uid() = user_id);

-- Settlements policies
DROP POLICY IF EXISTS "Users can view their settlements" ON settlements;
DROP POLICY IF EXISTS "Users can create settlements" ON settlements;

CREATE POLICY "Users can view their settlements"
ON settlements FOR SELECT
USING (auth.uid() = payer_id OR auth.uid() = payee_id);

CREATE POLICY "Users can create settlements"
ON settlements FOR INSERT WITH CHECK (auth.uid() = payer_id);

CREATE POLICY "Payee can mark as completed"
ON settlements FOR UPDATE USING (auth.uid() = payee_id);

-- ================================================================
-- INDEXES FOR PERFORMANCE
-- ================================================================

CREATE INDEX IF NOT EXISTS idx_id_verifications_user ON id_verifications(user_id);
CREATE INDEX IF NOT EXISTS idx_id_verifications_status ON id_verifications(verification_status);

CREATE INDEX IF NOT EXISTS idx_ride_links_user ON ride_links(user_id);
CREATE INDEX IF NOT EXISTS idx_ride_links_platform ON ride_links(platform);
CREATE INDEX IF NOT EXISTS idx_ride_links_created ON ride_links(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_cost_splits_creator ON cost_splits(created_by);
CREATE INDEX IF NOT EXISTS idx_cost_splits_status ON cost_splits(status);
CREATE INDEX IF NOT EXISTS idx_cost_splits_expires ON cost_splits(expires_at);
CREATE INDEX IF NOT EXISTS idx_cost_splits_token ON cost_splits(share_token);

CREATE INDEX IF NOT EXISTS idx_split_members_split ON split_members(split_id);
CREATE INDEX IF NOT EXISTS idx_split_members_user ON split_members(user_id);
CREATE INDEX IF NOT EXISTS idx_split_members_status ON split_members(payment_status);

CREATE INDEX IF NOT EXISTS idx_settlements_payer ON settlements(payer_id);
CREATE INDEX IF NOT EXISTS idx_settlements_payee ON settlements(payee_id);
CREATE INDEX IF NOT EXISTS idx_settlements_status ON settlements(status);
CREATE INDEX IF NOT EXISTS idx_settlements_split ON settlements(split_id);

-- ================================================================
-- HELPER FUNCTIONS
-- ================================================================

-- Function to get split details with members
CREATE OR REPLACE FUNCTION get_split_details(p_split_id UUID)
RETURNS TABLE(
  split_id UUID,
  created_by UUID,
  title TEXT,
  total_amount DECIMAL,
  member_count INT,
  amount_per_person DECIMAL,
  status TEXT,
  members jsonb
) AS $$
SELECT
  cs.id,
  cs.created_by,
  cs.title,
  cs.total_amount,
  COUNT(DISTINCT sm.id)::INT,
  cs.amount_per_person,
  cs.status,
  jsonb_agg(
    jsonb_build_object(
      'user_id', sm.user_id,
      'name', p.name,
      'amount_owed', sm.amount_owed,
      'amount_paid', sm.amount_paid,
      'status', sm.payment_status
    )
  ) FILTER (WHERE sm.id IS NOT NULL)
FROM cost_splits cs
LEFT JOIN split_members sm ON cs.id = sm.split_id
LEFT JOIN profiles p ON sm.user_id = p.id
WHERE cs.id = p_split_id
GROUP BY cs.id, cs.created_by, cs.title, cs.total_amount, cs.amount_per_person, cs.status;
$$ LANGUAGE SQL;

-- Function to generate shareable token
CREATE OR REPLACE FUNCTION generate_share_token()
RETURNS TEXT AS $$
BEGIN
  RETURN substr(md5(random()::text), 1, 32);
END;
$$ LANGUAGE plpgsql;

-- Function to calculate settlement amount
CREATE OR REPLACE FUNCTION calculate_settlement(p_split_id UUID, p_user_id UUID)
RETURNS DECIMAL AS $$
SELECT COALESCE(amount_owed - amount_paid, 0)
FROM split_members
WHERE split_id = p_split_id AND user_id = p_user_id;
$$ LANGUAGE SQL;

-- Trigger to auto-generate share token
CREATE OR REPLACE FUNCTION auto_generate_share_token()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.share_token IS NULL THEN
    NEW.share_token := substr(md5(random()::text || NEW.id::text), 1, 32);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_auto_share_token ON cost_splits;

CREATE TRIGGER trigger_auto_share_token
BEFORE INSERT ON cost_splits
FOR EACH ROW
EXECUTE FUNCTION auto_generate_share_token();

-- ================================================================
-- ENABLE REALTIME
-- ================================================================

ALTER PUBLICATION supabase_realtime ADD TABLE cost_splits;
ALTER PUBLICATION supabase_realtime ADD TABLE split_members;
ALTER PUBLICATION supabase_realtime ADD TABLE settlements;

SELECT '✅ Ride cost splitting database setup complete!' as status;
