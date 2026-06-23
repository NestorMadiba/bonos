# 📋 Instrucciones de Despliegue — Sistema Bonos Contribución

## 1. CONFIGURAR SUPABASE

### 1.1 Crear proyecto
1. Ir a https://supabase.com y crear cuenta gratuita
2. Crear un nuevo proyecto (anotar la contraseña de la base de datos)
3. Esperar que el proyecto se inicialice (~2 minutos)

### 1.2 Ejecutar el script SQL
1. En el panel de Supabase, ir a **SQL Editor** (ícono de base de datos)
2. Hacer clic en **New Query**
3. Pegar todo el contenido del archivo `supabase_schema.sql`
4. Hacer clic en **Run** (▶)
5. Verificar que no haya errores en los resultados

### 1.3 Obtener las credenciales
1. Ir a **Project Settings** → **API**
2. Copiar los valores:
   - **Project URL** → `https://XXXXXXXXXXXX.supabase.co`
   - **anon/public key** → la clave larga que empieza con `eyJ...`

### 1.4 Configurar autenticación
1. Ir a **Authentication** → **Settings**
2. En "Site URL" poner la URL de Vercel (la obtenés después del despliegue, ej. `https://bonos-colegio.vercel.app`)
3. En "Redirect URLs" agregar la misma URL

---

## 2. CREAR EL ADMINISTRADOR INICIAL

### Opción A: Desde Supabase Dashboard (recomendado)
1. Ir a **Authentication** → **Users** → **Invite User**
2. Ingresar el email del administrador
3. El admin recibirá un email para establecer su contraseña
4. Una vez que el admin haya completado el registro, ir a **SQL Editor** y ejecutar:

```sql
UPDATE public.profiles
SET role = 'admin'
WHERE email = 'TU_EMAIL_ADMIN@ejemplo.com';
```

### Opción B: Registro manual + promoción
1. Registrarse en la app como padre
2. Ir al SQL Editor de Supabase y ejecutar:
```sql
UPDATE public.profiles
SET role = 'admin'
WHERE email = 'TU_EMAIL@ejemplo.com';
```

---

## 3. DESPLEGAR EN VERCEL

### 3.1 Opción rápida (drag & drop)
1. Ir a https://vercel.com y crear cuenta con GitHub/Google
2. Ir a https://vercel.com/new
3. Seleccionar **"Deploy from scratch"** o usar la opción de importar
4. Arrastrar la carpeta con el `index.html` al área de Vercel

### 3.2 Opción con GitHub (recomendado para actualizaciones)
1. Crear un repositorio en GitHub
2. Subir el `index.html` al repositorio
3. En Vercel: **New Project** → importar el repositorio de GitHub
4. Vercel detectará automáticamente que es un sitio estático

### 3.3 Configurar las variables de entorno en Vercel
Esto no aplica para el frontend puro. En cambio, **editá directamente el index.html**:

Buscar estas líneas al inicio del JS:
```javascript
const SUPABASE_URL = window.SUPABASE_URL || 'https://TU_PROYECTO.supabase.co';
const SUPABASE_ANON_KEY = window.SUPABASE_ANON_KEY || 'TU_ANON_KEY';
```

Reemplazar con tus valores reales:
```javascript
const SUPABASE_URL = 'https://TUPROYECTO.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...';
```

> ⚠️ La `anon key` de Supabase es pública por diseño. La seguridad real está en las políticas RLS configuradas en la base de datos.

---

## 4. FLUJO DE USO RECOMENDADO

### Configuración inicial (admin):
1. **Configuración Anual** → Crear la configuración del año corriente (monto + cuotas)
2. **Alumnos** → Importar desde CSV o crear uno a uno
3. **Bonos** → Asignar bonos a los alumnos con su número correlativo
4. **Padres** → Vincular cuentas de padres con sus hijos (después de que se registren)

### Operación diaria:
- **Registrar pagos**: Ir a "Pagos" → buscar por nombre/DNI/N° bono → registrar
- **Consultar estado**: Ir a "Buscar Bonos" para cualquier bono del sistema
- **Reportes**: Ir a "Informes" y filtrar por año/grado

---

## 5. NUMERACIÓN DE BONOS

- Los bonos se numeran del `0000` al `1000`
- El administrador asigna manualmente el número al crear cada bono
- El sistema valida que no haya duplicados
- Se pueden buscar directamente por número en "Búsqueda Global"

---

## 6. IMPORTACIÓN CSV

### Formato del archivo:
```
dni,apellido,nombre,email
12345678,García,Juan,juan@email.com
87654321,López,María,
```

- La primera fila debe ser el encabezado
- El campo `email` es opcional
- Si el DNI ya existe, se actualizan los datos (upsert)
- Descargar la plantilla desde el sistema: Importar CSV → "Descargar Plantilla"

---

## 7. ESTRUCTURA DEL SISTEMA

### Roles de usuario:
| Rol | Permisos |
|-----|----------|
| **Admin** | Todo: ABM alumnos, configurar años, bonos, pagos, reportes, importar |
| **Padre** | Solo lectura: ver dashboard de sus hijos vinculados |

### Grados del sistema:
- Primaria: 4to, 5to, 6to
- Secundaria: 1ro, 2do, 3ro, 4to, **5to** (con bonos extra)

### Estados de bonos:
- 🔴 **Pendiente**: Sin pagos registrados
- 🟠 **Parcial**: Con pagos pero sin cancelar
- 🟢 **Pagado**: Cancelado completamente

---

## 8. SEGURIDAD (RLS)

Las políticas de seguridad en Supabase garantizan que:
- Los **padres** solo ven datos de sus hijos vinculados
- Los **padres** NO pueden insertar, modificar ni eliminar nada
- Los **admins** tienen acceso completo
- Esto se aplica **en la base de datos**, no solo en el frontend

---

## 9. SOPORTE Y MANTENIMIENTO

### Backup de datos:
- Supabase gratuito incluye backups automáticos diarios
- Para exportar manualmente: Dashboard → Database → Backups

### Actualizar el sistema:
- Editar el `index.html` y volver a subir a Vercel
- Los cambios en el SQL deben ejecutarse en el SQL Editor de Supabase

---

## ✅ CHECKLIST DE DESPLIEGUE

- [ ] Proyecto Supabase creado
- [ ] Script SQL ejecutado sin errores
- [ ] Admin creado y promovido con `UPDATE profiles SET role = 'admin'`
- [ ] `SUPABASE_URL` y `SUPABASE_ANON_KEY` actualizados en `index.html`
- [ ] `index.html` desplegado en Vercel
- [ ] URL de Vercel configurada en Supabase Authentication → Site URL
- [ ] Primera configuración de año creada
- [ ] Prueba de login como admin ✓
- [ ] Prueba de registro como padre ✓
- [ ] Prueba de vinculación padre-alumno ✓
