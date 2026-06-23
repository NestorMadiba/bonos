-- ============================================================
-- SISTEMA BONOS CONTRIBUCIÓN - SCRIPT SQL PARA SUPABASE
-- Ejecutar en: Supabase > SQL Editor
-- ============================================================

-- ─── EXTENSIONES ────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ─── ENUM TYPES ─────────────────────────────────────────────
CREATE TYPE payment_method AS ENUM ('efectivo', 'tarjeta');
CREATE TYPE bond_status AS ENUM ('pendiente', 'parcial', 'pagado');
CREATE TYPE user_role AS ENUM ('admin', 'padre');

-- ─── TABLA: profiles ────────────────────────────────────────
-- Extiende auth.users con datos adicionales
CREATE TABLE public.profiles (
  id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email       TEXT NOT NULL,
  full_name   TEXT NOT NULL,
  role        user_role NOT NULL DEFAULT 'padre',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── TABLA: year_config ─────────────────────────────────────
-- Configuración anual: monto del bono y cantidad de cuotas
CREATE TABLE public.year_config (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  year            INTEGER NOT NULL UNIQUE,
  total_amount    NUMERIC(12,2) NOT NULL,
  installments    INTEGER NOT NULL DEFAULT 4,
  created_by      UUID REFERENCES public.profiles(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── TABLA: students ────────────────────────────────────────
CREATE TABLE public.students (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  dni         TEXT NOT NULL UNIQUE,
  first_name  TEXT NOT NULL,
  last_name   TEXT NOT NULL,
  email       TEXT,
  phone       TEXT,
  notes       TEXT,
  created_by  UUID REFERENCES public.profiles(id),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── TABLA: enrollments ─────────────────────────────────────
-- Qué grado cursó el alumno en qué año lectivo
CREATE TABLE public.enrollments (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  student_id  UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  year_config_id UUID NOT NULL REFERENCES public.year_config(id),
  grade       TEXT NOT NULL,  -- '4to Primaria', '1ro Secundaria', etc.
  created_by  UUID REFERENCES public.profiles(id),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(student_id, year_config_id)
);

-- ─── TABLA: bonds ───────────────────────────────────────────
-- Cada bono (anual o extra de 5to Secundaria)
CREATE TABLE public.bonds (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  bond_number     CHAR(4) NOT NULL UNIQUE,  -- '0001' a '1000'
  student_id      UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  year_config_id  UUID NOT NULL REFERENCES public.year_config(id),
  grade           TEXT NOT NULL,
  is_extra        BOOLEAN NOT NULL DEFAULT FALSE,  -- TRUE = bono extra de 5to
  total_amount    NUMERIC(12,2) NOT NULL,
  amount_paid     NUMERIC(12,2) NOT NULL DEFAULT 0,
  status          bond_status NOT NULL DEFAULT 'pendiente',
  created_by      UUID REFERENCES public.profiles(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Índices para bonds
CREATE INDEX idx_bonds_student_id ON public.bonds(student_id);
CREATE INDEX idx_bonds_year_config_id ON public.bonds(year_config_id);
CREATE INDEX idx_bonds_bond_number ON public.bonds(bond_number);
CREATE INDEX idx_bonds_status ON public.bonds(status);

-- ─── TABLA: payments ────────────────────────────────────────
CREATE TABLE public.payments (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  bond_id         UUID NOT NULL REFERENCES public.bonds(id) ON DELETE CASCADE,
  amount          NUMERIC(12,2) NOT NULL,
  payment_date    DATE NOT NULL DEFAULT CURRENT_DATE,
  method          payment_method NOT NULL,
  observations    TEXT,
  registered_by   UUID REFERENCES public.profiles(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_payments_bond_id ON public.payments(bond_id);
CREATE INDEX idx_payments_date ON public.payments(payment_date);

-- ─── TABLA: parent_students ─────────────────────────────────
-- Vinculación padres ↔ alumnos
CREATE TABLE public.parent_students (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  parent_id   UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  student_id  UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  linked_by   UUID REFERENCES public.profiles(id),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(parent_id, student_id)
);

CREATE INDEX idx_parent_students_parent ON public.parent_students(parent_id);
CREATE INDEX idx_parent_students_student ON public.parent_students(student_id);

-- ─── TABLA: audit_log ───────────────────────────────────────
CREATE TABLE public.audit_log (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID REFERENCES public.profiles(id),
  action      TEXT NOT NULL,
  table_name  TEXT NOT NULL,
  record_id   UUID,
  old_data    JSONB,
  new_data    JSONB,
  ip_address  TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audit_log_user ON public.audit_log(user_id);
CREATE INDEX idx_audit_log_table ON public.audit_log(table_name);
CREATE INDEX idx_audit_log_created ON public.audit_log(created_at DESC);

-- ─── FUNCIÓN: actualizar updated_at ─────────────────────────
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers updated_at
CREATE TRIGGER trg_profiles_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_year_config_updated_at BEFORE UPDATE ON public.year_config FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_students_updated_at BEFORE UPDATE ON public.students FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_bonds_updated_at BEFORE UPDATE ON public.bonds FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ─── FUNCIÓN: recalcular estado del bono ────────────────────
CREATE OR REPLACE FUNCTION recalculate_bond_status()
RETURNS TRIGGER AS $$
DECLARE
  v_total     NUMERIC(12,2);
  v_paid      NUMERIC(12,2);
  v_status    bond_status;
BEGIN
  SELECT total_amount INTO v_total FROM public.bonds WHERE id = NEW.bond_id;
  SELECT COALESCE(SUM(amount), 0) INTO v_paid FROM public.payments WHERE bond_id = NEW.bond_id;

  IF v_paid <= 0 THEN
    v_status := 'pendiente';
  ELSIF v_paid >= v_total THEN
    v_status := 'pagado';
  ELSE
    v_status := 'parcial';
  END IF;

  UPDATE public.bonds
  SET amount_paid = v_paid, status = v_status, updated_at = NOW()
  WHERE id = NEW.bond_id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_payment_update_bond
AFTER INSERT OR UPDATE OR DELETE ON public.payments
FOR EACH ROW EXECUTE FUNCTION recalculate_bond_status();

-- ─── FUNCIÓN: crear profile al registrar usuario ────────────
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name, role)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email),
    COALESCE((NEW.raw_user_meta_data->>'role')::user_role, 'padre')
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ─── FUNCIÓN HELPER: verificar si es admin ──────────────────
CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'admin'
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- ─── HABILITAR RLS EN TODAS LAS TABLAS ──────────────────────
ALTER TABLE public.profiles       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.year_config    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.students       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.enrollments    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bonds          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.parent_students ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log      ENABLE ROW LEVEL SECURITY;

-- ─── POLÍTICAS RLS: profiles ────────────────────────────────
CREATE POLICY "Admin full access profiles" ON public.profiles
  FOR ALL USING (is_admin()) WITH CHECK (is_admin());

CREATE POLICY "User can view own profile" ON public.profiles
  FOR SELECT USING (id = auth.uid());

CREATE POLICY "User can update own profile" ON public.profiles
  FOR UPDATE USING (id = auth.uid()) WITH CHECK (id = auth.uid());

-- ─── POLÍTICAS RLS: year_config ─────────────────────────────
CREATE POLICY "Admin full year_config" ON public.year_config
  FOR ALL USING (is_admin()) WITH CHECK (is_admin());

CREATE POLICY "Padre can read year_config" ON public.year_config
  FOR SELECT USING (auth.uid() IS NOT NULL);

-- ─── POLÍTICAS RLS: students ────────────────────────────────
CREATE POLICY "Admin full students" ON public.students
  FOR ALL USING (is_admin()) WITH CHECK (is_admin());

CREATE POLICY "Padre can see own linked students" ON public.students
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.parent_students ps
      WHERE ps.student_id = students.id AND ps.parent_id = auth.uid()
    )
  );

-- ─── POLÍTICAS RLS: enrollments ─────────────────────────────
CREATE POLICY "Admin full enrollments" ON public.enrollments
  FOR ALL USING (is_admin()) WITH CHECK (is_admin());

CREATE POLICY "Padre can see enrollments of linked students" ON public.enrollments
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.parent_students ps
      WHERE ps.student_id = enrollments.student_id AND ps.parent_id = auth.uid()
    )
  );

-- ─── POLÍTICAS RLS: bonds ───────────────────────────────────
CREATE POLICY "Admin full bonds" ON public.bonds
  FOR ALL USING (is_admin()) WITH CHECK (is_admin());

CREATE POLICY "Padre can see bonds of linked students" ON public.bonds
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.parent_students ps
      WHERE ps.student_id = bonds.student_id AND ps.parent_id = auth.uid()
    )
  );

-- ─── POLÍTICAS RLS: payments ────────────────────────────────
CREATE POLICY "Admin full payments" ON public.payments
  FOR ALL USING (is_admin()) WITH CHECK (is_admin());

CREATE POLICY "Padre can see payments of linked students bonds" ON public.payments
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.bonds b
      JOIN public.parent_students ps ON ps.student_id = b.student_id
      WHERE b.id = payments.bond_id AND ps.parent_id = auth.uid()
    )
  );

-- ─── POLÍTICAS RLS: parent_students ─────────────────────────
CREATE POLICY "Admin full parent_students" ON public.parent_students
  FOR ALL USING (is_admin()) WITH CHECK (is_admin());

CREATE POLICY "Padre can see own links" ON public.parent_students
  FOR SELECT USING (parent_id = auth.uid());

-- ─── POLÍTICAS RLS: audit_log ───────────────────────────────
CREATE POLICY "Admin full audit_log" ON public.audit_log
  FOR ALL USING (is_admin()) WITH CHECK (is_admin());

-- ─── DATOS SEMILLA: Configuración años ──────────────────────
-- NOTA: El admin de prueba se crea en la siguiente sección
INSERT INTO public.year_config (year, total_amount, installments)
VALUES
  (2024, 180000, 4),
  (2025, 240000, 4),
  (2026, 300000, 4);

-- ─── SCRIPT PARA CREAR ADMIN DE PRUEBA ──────────────────────
-- Ejecutar DESPUÉS de que el usuario se registre vía la app,
-- o usar la función de Supabase Auth Admin.
-- Para promover un usuario existente a admin:
--
-- UPDATE public.profiles
-- SET role = 'admin'
-- WHERE email = 'admin@colegio.edu.ar';
--
-- O crear un usuario admin directamente via Supabase Dashboard:
-- Authentication > Users > Invite User
-- Luego ejecutar el UPDATE de arriba.

-- ─── VISTAS ÚTILES ──────────────────────────────────────────

-- Vista: resumen de bonos por alumno
CREATE OR REPLACE VIEW public.student_bond_summary AS
SELECT
  s.id AS student_id,
  s.dni,
  s.first_name,
  s.last_name,
  COUNT(b.id) AS total_bonds,
  COUNT(b.id) FILTER (WHERE b.status = 'pagado') AS paid_bonds,
  COUNT(b.id) FILTER (WHERE b.status = 'pendiente') AS pending_bonds,
  COUNT(b.id) FILTER (WHERE b.status = 'parcial') AS partial_bonds,
  SUM(b.total_amount) AS total_amount,
  SUM(b.amount_paid) AS total_paid,
  SUM(b.total_amount - b.amount_paid) AS total_balance,
  CASE
    WHEN COUNT(b.id) > 0 AND COUNT(b.id) = COUNT(b.id) FILTER (WHERE b.status = 'pagado')
    THEN TRUE ELSE FALSE
  END AS debt_free
FROM public.students s
LEFT JOIN public.bonds b ON b.student_id = s.id
GROUP BY s.id, s.dni, s.first_name, s.last_name;

-- ─── FIN DEL SCRIPT ─────────────────────────────────────────
-- Total tablas: profiles, year_config, students, enrollments,
--               bonds, payments, parent_students, audit_log
-- Total políticas RLS: 16
-- Triggers: updated_at (4) + bond_status (1) + new_user (1)
