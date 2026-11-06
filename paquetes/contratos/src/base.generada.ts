// Eskemia · Tipos del esquema api, GENERADOS por scripts/generar-tipos.sh.
// No editar a mano: se regeneran después de cada migración que cambie el esquema api.

export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  api: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      adjuntos: {
        Row: {
          anulado_en: string | null
          client_uuid: string | null
          creado_en: string | null
          id: string | null
          item_id: string | null
          organizacion_id: string | null
          recepcion_id: string | null
          sede_id: string | null
          storage_path: string | null
          tipo:
            | "REMITO"
            | "RECHAZO"
            | "MANUAL"
            | "FIRMA_RECEPTOR"
            | "FIRMA_TRANSPORTISTA"
            | null
          usuario_id: string | null
        }
        ComputedFields: never
        Insert: {
          anulado_en?: string | null
          client_uuid?: string | null
          creado_en?: string | null
          id?: string | null
          item_id?: string | null
          organizacion_id?: string | null
          recepcion_id?: string | null
          sede_id?: string | null
          storage_path?: string | null
          tipo?:
            | "REMITO"
            | "RECHAZO"
            | "MANUAL"
            | "FIRMA_RECEPTOR"
            | "FIRMA_TRANSPORTISTA"
            | null
          usuario_id?: string | null
        }
        Update: {
          anulado_en?: string | null
          client_uuid?: string | null
          creado_en?: string | null
          id?: string | null
          item_id?: string | null
          organizacion_id?: string | null
          recepcion_id?: string | null
          sede_id?: string | null
          storage_path?: string | null
          tipo?:
            | "REMITO"
            | "RECHAZO"
            | "MANUAL"
            | "FIRMA_RECEPTOR"
            | "FIRMA_TRANSPORTISTA"
            | null
          usuario_id?: string | null
        }
        Relationships: []
      }
      categorias: {
        Row: {
          activo: boolean | null
          creado_en: string | null
          id: string | null
          nombre: string | null
          orden: number | null
          organizacion_id: string | null
          rubro_id: string | null
          sede_id: string | null
        }
        ComputedFields: never
        Insert: {
          activo?: boolean | null
          creado_en?: string | null
          id?: string | null
          nombre?: string | null
          orden?: number | null
          organizacion_id?: string | null
          rubro_id?: string | null
          sede_id?: string | null
        }
        Update: {
          activo?: boolean | null
          creado_en?: string | null
          id?: string | null
          nombre?: string | null
          orden?: number | null
          organizacion_id?: string | null
          rubro_id?: string | null
          sede_id?: string | null
        }
        Relationships: []
      }
      configuracion_compras: {
        Row: {
          actualizado_en: string | null
          organizacion_id: string | null
          permitir_autoaprobacion: boolean | null
        }
        ComputedFields: never
        Insert: {
          actualizado_en?: string | null
          organizacion_id?: string | null
          permitir_autoaprobacion?: boolean | null
        }
        Update: {
          actualizado_en?: string | null
          organizacion_id?: string | null
          permitir_autoaprobacion?: boolean | null
        }
        Relationships: []
      }
      eventos: {
        Row: {
          accion: string | null
          creado_en: string | null
          dispositivo_id: string | null
          entidad: string | null
          entidad_id: string | null
          id: string | null
          organizacion_id: string | null
          payload: Json | null
          secuencia: number | null
          sede_id: string | null
          usuario: string | null
          usuario_id: string | null
        }
        ComputedFields: never
        Insert: {
          accion?: string | null
          creado_en?: string | null
          dispositivo_id?: string | null
          entidad?: string | null
          entidad_id?: string | null
          id?: string | null
          organizacion_id?: string | null
          payload?: Json | null
          secuencia?: number | null
          sede_id?: string | null
          usuario?: never
          usuario_id?: string | null
        }
        Update: {
          accion?: string | null
          creado_en?: string | null
          dispositivo_id?: string | null
          entidad?: string | null
          entidad_id?: string | null
          id?: string | null
          organizacion_id?: string | null
          payload?: Json | null
          secuencia?: number | null
          sede_id?: string | null
          usuario?: never
          usuario_id?: string | null
        }
        Relationships: []
      }
      lecturas: {
        Row: {
          cantidad: number | null
          client_uuid: string | null
          creado_en: string | null
          dispositivo_id: string | null
          id: string | null
          item_id: string | null
          leido_en: string | null
          motivo: string | null
          organizacion_id: string | null
          producto_id: string | null
          recepcion_id: string | null
          sede_id: string | null
          tipo: "ESCANEO" | "MANUAL" | "PESAJE" | null
          valor_crudo: string | null
        }
        ComputedFields: never
        Insert: {
          cantidad?: number | null
          client_uuid?: string | null
          creado_en?: string | null
          dispositivo_id?: string | null
          id?: string | null
          item_id?: string | null
          leido_en?: string | null
          motivo?: string | null
          organizacion_id?: string | null
          producto_id?: string | null
          recepcion_id?: string | null
          sede_id?: string | null
          tipo?: "ESCANEO" | "MANUAL" | "PESAJE" | null
          valor_crudo?: string | null
        }
        Update: {
          cantidad?: number | null
          client_uuid?: string | null
          creado_en?: string | null
          dispositivo_id?: string | null
          id?: string | null
          item_id?: string | null
          leido_en?: string | null
          motivo?: string | null
          organizacion_id?: string | null
          producto_id?: string | null
          recepcion_id?: string | null
          sede_id?: string | null
          tipo?: "ESCANEO" | "MANUAL" | "PESAJE" | null
          valor_crudo?: string | null
        }
        Relationships: []
      }
      membresia_roles: {
        Row: {
          cuenta_id: string | null
          id: string | null
          membresia_id: string | null
          organizacion_id: string | null
          rol: string | null
          rol_id: string | null
          sector_id: string | null
          sede_id: string | null
        }
        ComputedFields: never
        Relationships: []
      }
      mi_cuenta: {
        Row: {
          alias: string | null
          alias_visible: boolean | null
          apellido: string | null
          avatar_path: string | null
          creada_en: string | null
          id: string | null
          idioma: string | null
          nombre: string | null
          zona_horaria: string | null
        }
        ComputedFields: never
        Insert: {
          alias?: string | null
          alias_visible?: boolean | null
          apellido?: string | null
          avatar_path?: string | null
          creada_en?: string | null
          id?: string | null
          idioma?: string | null
          nombre?: string | null
          zona_horaria?: string | null
        }
        Update: {
          alias?: string | null
          alias_visible?: boolean | null
          apellido?: string | null
          avatar_path?: string | null
          creada_en?: string | null
          id?: string | null
          idioma?: string | null
          nombre?: string | null
          zona_horaria?: string | null
        }
        Relationships: []
      }
      mi_inicio: {
        Row: {
          orden: number | null
          organizacion_id: string | null
          tarjeta_codigo: string | null
          visible: boolean | null
        }
        ComputedFields: never
        Insert: {
          orden?: number | null
          organizacion_id?: string | null
          tarjeta_codigo?: string | null
          visible?: boolean | null
        }
        Update: {
          orden?: number | null
          organizacion_id?: string | null
          tarjeta_codigo?: string | null
          visible?: boolean | null
        }
        Relationships: []
      }
      miembros: {
        Row: {
          alias: string | null
          apellido: string | null
          avatar_path: string | null
          cuenta_id: string | null
          es_titular: boolean | null
          estado: string | null
          membresia_id: string | null
          nombre: string | null
          organizacion_id: string | null
          puesto: string | null
          puesto_id: string | null
          unida_en: string | null
        }
        ComputedFields: never
        Relationships: []
      }
      mis_organizaciones: {
        Row: {
          descripcion: string | null
          estado: string | null
          id: string | null
          logo_path: string | null
          membresia_id: string | null
          nombre: string | null
          puesto: string | null
          puesto_id: string | null
          slug: string | null
          soy_titular: boolean | null
          unida_en: string | null
        }
        ComputedFields: never
        Relationships: []
      }
      modulos_habilitados: {
        Row: {
          codigo: string | null
          descripcion: string | null
          habilitado_en: string | null
          nombre: string | null
          organizacion_id: string | null
        }
        ComputedFields: never
        Relationships: []
      }
      oc_items: {
        Row: {
          cant_pedida: number | null
          cantidad: number | null
          disparo_aprobacion: boolean | null
          factor: number | null
          id: string | null
          oc_id: string | null
          organizacion_id: string | null
          precio_unitario: number | null
          presentacion_id: string | null
          presentacion_nombre: string | null
          producto_id: string | null
          producto_nombre: string | null
          producto_proveedor_id: string | null
          sede_id: string | null
          sku: string | null
          subtotal: number | null
        }
        ComputedFields: never
        Insert: {
          cant_pedida?: number | null
          cantidad?: number | null
          disparo_aprobacion?: boolean | null
          factor?: number | null
          id?: string | null
          oc_id?: string | null
          organizacion_id?: string | null
          precio_unitario?: number | null
          presentacion_id?: string | null
          presentacion_nombre?: string | null
          producto_id?: string | null
          producto_nombre?: string | null
          producto_proveedor_id?: string | null
          sede_id?: string | null
          sku?: string | null
          subtotal?: number | null
        }
        Update: {
          cant_pedida?: number | null
          cantidad?: number | null
          disparo_aprobacion?: boolean | null
          factor?: number | null
          id?: string | null
          oc_id?: string | null
          organizacion_id?: string | null
          precio_unitario?: number | null
          presentacion_id?: string | null
          presentacion_nombre?: string | null
          producto_id?: string | null
          producto_nombre?: string | null
          producto_proveedor_id?: string | null
          sede_id?: string | null
          sku?: string | null
          subtotal?: number | null
        }
        Relationships: []
      }
      oc_saldos: {
        Row: {
          cant_pedida: number | null
          cant_recibida: number | null
          oc_id: string | null
          organizacion_id: string | null
          producto_id: string | null
          producto_nombre: string | null
          sede_id: string | null
          sku: string | null
        }
        ComputedFields: never
        Relationships: []
      }
      ordenes_compra: {
        Row: {
          aprobada_en: string | null
          aprobada_por: string | null
          canal_envio: "MANUAL" | "WHATSAPP" | "EMAIL" | null
          creado_en: string | null
          enviada_en: string | null
          estado:
            | "PENDIENTE_APROBACION"
            | "APROBADA"
            | "RECHAZADA"
            | "ENVIADA"
            | "RECIBIDA_PARCIAL"
            | "RECIBIDA"
            | "CERRADA"
            | "ANULADA"
            | null
          fecha_entrega_estimada: string | null
          id: string | null
          motivo_cierre: string | null
          motivo_rechazo: string | null
          nivel_requerido: number | null
          numero: string | null
          organizacion_id: string | null
          pedido_id: string | null
          proveedor_id: string | null
          reglas_aplicadas: Json | null
          requiere_aprobacion: boolean | null
          sede_id: string | null
          tipo_aprobacion: "AUTOMATICA" | "AUTOAPROBADA" | "MANUAL" | null
          total_estimado: number | null
          usuario_id: string | null
        }
        ComputedFields: never
        Insert: {
          aprobada_en?: string | null
          aprobada_por?: string | null
          canal_envio?: "MANUAL" | "WHATSAPP" | "EMAIL" | null
          creado_en?: string | null
          enviada_en?: string | null
          estado?:
            | "PENDIENTE_APROBACION"
            | "APROBADA"
            | "RECHAZADA"
            | "ENVIADA"
            | "RECIBIDA_PARCIAL"
            | "RECIBIDA"
            | "CERRADA"
            | "ANULADA"
            | null
          fecha_entrega_estimada?: string | null
          id?: string | null
          motivo_cierre?: string | null
          motivo_rechazo?: string | null
          nivel_requerido?: number | null
          numero?: string | null
          organizacion_id?: string | null
          pedido_id?: string | null
          proveedor_id?: string | null
          reglas_aplicadas?: Json | null
          requiere_aprobacion?: boolean | null
          sede_id?: string | null
          tipo_aprobacion?: "AUTOMATICA" | "AUTOAPROBADA" | "MANUAL" | null
          total_estimado?: number | null
          usuario_id?: string | null
        }
        Update: {
          aprobada_en?: string | null
          aprobada_por?: string | null
          canal_envio?: "MANUAL" | "WHATSAPP" | "EMAIL" | null
          creado_en?: string | null
          enviada_en?: string | null
          estado?:
            | "PENDIENTE_APROBACION"
            | "APROBADA"
            | "RECHAZADA"
            | "ENVIADA"
            | "RECIBIDA_PARCIAL"
            | "RECIBIDA"
            | "CERRADA"
            | "ANULADA"
            | null
          fecha_entrega_estimada?: string | null
          id?: string | null
          motivo_cierre?: string | null
          motivo_rechazo?: string | null
          nivel_requerido?: number | null
          numero?: string | null
          organizacion_id?: string | null
          pedido_id?: string | null
          proveedor_id?: string | null
          reglas_aplicadas?: Json | null
          requiere_aprobacion?: boolean | null
          sede_id?: string | null
          tipo_aprobacion?: "AUTOMATICA" | "AUTOAPROBADA" | "MANUAL" | null
          total_estimado?: number | null
          usuario_id?: string | null
        }
        Relationships: []
      }
      pedido_items: {
        Row: {
          cantidad: number | null
          id: string | null
          organizacion_id: string | null
          pedido_id: string | null
          presentacion_id: string | null
          producto_proveedor_id: string | null
        }
        ComputedFields: never
        Insert: {
          cantidad?: number | null
          id?: string | null
          organizacion_id?: string | null
          pedido_id?: string | null
          presentacion_id?: string | null
          producto_proveedor_id?: string | null
        }
        Update: {
          cantidad?: number | null
          id?: string | null
          organizacion_id?: string | null
          pedido_id?: string | null
          presentacion_id?: string | null
          producto_proveedor_id?: string | null
        }
        Relationships: []
      }
      pedidos_compra: {
        Row: {
          confirmado_en: string | null
          creado_en: string | null
          estado: "BORRADOR" | "CONFIRMADO" | "DESCARTADO" | null
          id: string | null
          organizacion_id: string | null
          request_uuid: string | null
          sector_id: string | null
          sede_id: string | null
          usuario_id: string | null
        }
        ComputedFields: never
        Insert: {
          confirmado_en?: string | null
          creado_en?: string | null
          estado?: "BORRADOR" | "CONFIRMADO" | "DESCARTADO" | null
          id?: string | null
          organizacion_id?: string | null
          request_uuid?: string | null
          sector_id?: string | null
          sede_id?: string | null
          usuario_id?: string | null
        }
        Update: {
          confirmado_en?: string | null
          creado_en?: string | null
          estado?: "BORRADOR" | "CONFIRMADO" | "DESCARTADO" | null
          id?: string | null
          organizacion_id?: string | null
          request_uuid?: string | null
          sector_id?: string | null
          sede_id?: string | null
          usuario_id?: string | null
        }
        Relationships: []
      }
      permisos: {
        Row: {
          codigo: string | null
          descripcion: string | null
          modulo: string | null
        }
        ComputedFields: never
        Insert: {
          codigo?: string | null
          descripcion?: string | null
          modulo?: string | null
        }
        Update: {
          codigo?: string | null
          descripcion?: string | null
          modulo?: string | null
        }
        Relationships: []
      }
      presentaciones: {
        Row: {
          activa: boolean | null
          creado_en: string | null
          factor: number | null
          id: string | null
          nombre: string | null
          organizacion_id: string | null
          producto_id: string | null
        }
        ComputedFields: never
        Insert: {
          activa?: boolean | null
          creado_en?: string | null
          factor?: number | null
          id?: string | null
          nombre?: string | null
          organizacion_id?: string | null
          producto_id?: string | null
        }
        Update: {
          activa?: boolean | null
          creado_en?: string | null
          factor?: number | null
          id?: string | null
          nombre?: string | null
          organizacion_id?: string | null
          producto_id?: string | null
        }
        Relationships: []
      }
      producto_codigos: {
        Row: {
          codigo: string | null
          codigo_busqueda: string | null
          creado_en: string | null
          id: string | null
          organizacion_id: string | null
          presentacion_id: string | null
          producto_id: string | null
          tipo:
            | "EAN13"
            | "EAN8"
            | "DUN14"
            | "GS1_128"
            | "UPC"
            | "INTERNO"
            | null
        }
        ComputedFields: never
        Insert: {
          codigo?: string | null
          codigo_busqueda?: string | null
          creado_en?: string | null
          id?: string | null
          organizacion_id?: string | null
          presentacion_id?: string | null
          producto_id?: string | null
          tipo?:
            | "EAN13"
            | "EAN8"
            | "DUN14"
            | "GS1_128"
            | "UPC"
            | "INTERNO"
            | null
        }
        Update: {
          codigo?: string | null
          codigo_busqueda?: string | null
          creado_en?: string | null
          id?: string | null
          organizacion_id?: string | null
          presentacion_id?: string | null
          producto_id?: string | null
          tipo?:
            | "EAN13"
            | "EAN8"
            | "DUN14"
            | "GS1_128"
            | "UPC"
            | "INTERNO"
            | null
        }
        Relationships: []
      }
      producto_proveedor: {
        Row: {
          activo: boolean | null
          codigo_proveedor: string | null
          creado_en: string | null
          id: string | null
          organizacion_id: string | null
          precio_actual: number | null
          preferido: boolean | null
          presentacion_id: string | null
          producto_id: string | null
          proveedor_id: string | null
        }
        ComputedFields: never
        Insert: {
          activo?: boolean | null
          codigo_proveedor?: string | null
          creado_en?: string | null
          id?: string | null
          organizacion_id?: string | null
          precio_actual?: number | null
          preferido?: boolean | null
          presentacion_id?: string | null
          producto_id?: string | null
          proveedor_id?: string | null
        }
        Update: {
          activo?: boolean | null
          codigo_proveedor?: string | null
          creado_en?: string | null
          id?: string | null
          organizacion_id?: string | null
          precio_actual?: number | null
          preferido?: boolean | null
          presentacion_id?: string | null
          producto_id?: string | null
          proveedor_id?: string | null
        }
        Relationships: []
      }
      productos: {
        Row: {
          activo: boolean | null
          categoria_id: string | null
          creado_en: string | null
          gtin: string | null
          id: string | null
          nombre: string | null
          organizacion_id: string | null
          pendiente_validacion: boolean | null
          requiere_lote: boolean | null
          requiere_vencimiento: boolean | null
          sede_id: string | null
          sku: string | null
          tipo_medida: "UNIDAD" | "PESO" | null
          unidad_stock: "UN" | "KG" | "LT" | null
        }
        ComputedFields: never
        Insert: {
          activo?: boolean | null
          categoria_id?: string | null
          creado_en?: string | null
          gtin?: string | null
          id?: string | null
          nombre?: string | null
          organizacion_id?: string | null
          pendiente_validacion?: boolean | null
          requiere_lote?: boolean | null
          requiere_vencimiento?: boolean | null
          sede_id?: string | null
          sku?: string | null
          tipo_medida?: "UNIDAD" | "PESO" | null
          unidad_stock?: "UN" | "KG" | "LT" | null
        }
        Update: {
          activo?: boolean | null
          categoria_id?: string | null
          creado_en?: string | null
          gtin?: string | null
          id?: string | null
          nombre?: string | null
          organizacion_id?: string | null
          pendiente_validacion?: boolean | null
          requiere_lote?: boolean | null
          requiere_vencimiento?: boolean | null
          sede_id?: string | null
          sku?: string | null
          tipo_medida?: "UNIDAD" | "PESO" | null
          unidad_stock?: "UN" | "KG" | "LT" | null
        }
        Relationships: []
      }
      proveedores: {
        Row: {
          activo: boolean | null
          canal_envio: "MANUAL" | "WHATSAPP" | "EMAIL" | null
          codigo: string | null
          contacto: string | null
          creado_en: string | null
          cuit: string | null
          dias_pedido: number[] | null
          email: string | null
          id: string | null
          monto_minimo: number | null
          nombre: string | null
          organizacion_id: string | null
          plazo_entrega_dias: number | null
          sede_id: string | null
          telefono_whatsapp: string | null
        }
        ComputedFields: never
        Insert: {
          activo?: boolean | null
          canal_envio?: "MANUAL" | "WHATSAPP" | "EMAIL" | null
          codigo?: string | null
          contacto?: string | null
          creado_en?: string | null
          cuit?: string | null
          dias_pedido?: number[] | null
          email?: string | null
          id?: string | null
          monto_minimo?: number | null
          nombre?: string | null
          organizacion_id?: string | null
          plazo_entrega_dias?: number | null
          sede_id?: string | null
          telefono_whatsapp?: string | null
        }
        Update: {
          activo?: boolean | null
          canal_envio?: "MANUAL" | "WHATSAPP" | "EMAIL" | null
          codigo?: string | null
          contacto?: string | null
          creado_en?: string | null
          cuit?: string | null
          dias_pedido?: number[] | null
          email?: string | null
          id?: string | null
          monto_minimo?: number | null
          nombre?: string | null
          organizacion_id?: string | null
          plazo_entrega_dias?: number | null
          sede_id?: string | null
          telefono_whatsapp?: string | null
        }
        Relationships: []
      }
      puestos: {
        Row: {
          id: string | null
          nombre: string | null
          orden: number | null
          organizacion_id: string | null
          rol_sugerido: string | null
        }
        ComputedFields: never
        Insert: {
          id?: string | null
          nombre?: string | null
          orden?: number | null
          organizacion_id?: string | null
          rol_sugerido?: string | null
        }
        Update: {
          id?: string | null
          nombre?: string | null
          orden?: number | null
          organizacion_id?: string | null
          rol_sugerido?: string | null
        }
        Relationships: []
      }
      recepcion_items: {
        Row: {
          cant_pedida: number | null
          cant_recibida: number | null
          cant_remito: number | null
          creado_en: string | null
          diferencia: number | null
          id: string | null
          lote: string | null
          motivo_diferencia: string | null
          organizacion_id: string | null
          producto_id: string | null
          recepcion_id: string | null
          sede_id: string | null
          tipo_diferencia:
            | "FALTANTE"
            | "SOBRANTE"
            | "RECHAZO"
            | "NO_PEDIDO"
            | "SUSTITUCION"
            | null
          vencimiento: string | null
        }
        ComputedFields: never
        Insert: {
          cant_pedida?: number | null
          cant_recibida?: number | null
          cant_remito?: number | null
          creado_en?: string | null
          diferencia?: number | null
          id?: string | null
          lote?: string | null
          motivo_diferencia?: string | null
          organizacion_id?: string | null
          producto_id?: string | null
          recepcion_id?: string | null
          sede_id?: string | null
          tipo_diferencia?:
            | "FALTANTE"
            | "SOBRANTE"
            | "RECHAZO"
            | "NO_PEDIDO"
            | "SUSTITUCION"
            | null
          vencimiento?: string | null
        }
        Update: {
          cant_pedida?: number | null
          cant_recibida?: number | null
          cant_remito?: number | null
          creado_en?: string | null
          diferencia?: number | null
          id?: string | null
          lote?: string | null
          motivo_diferencia?: string | null
          organizacion_id?: string | null
          producto_id?: string | null
          recepcion_id?: string | null
          sede_id?: string | null
          tipo_diferencia?:
            | "FALTANTE"
            | "SOBRANTE"
            | "RECHAZO"
            | "NO_PEDIDO"
            | "SUSTITUCION"
            | null
          vencimiento?: string | null
        }
        Relationships: []
      }
      recepciones: {
        Row: {
          abierta_en: string | null
          cerrada_en: string | null
          creado_en: string | null
          estado:
            | "ABIERTA"
            | "EN_CONTROL"
            | "CERRADA_OK"
            | "CERRADA_CON_DIFERENCIAS"
            | "VALIDADA"
            | "INGRESADA_A_SISTEMA"
            | "RECHAZADA"
            | null
          id: string | null
          nro_remito: string | null
          observacion: string | null
          oc_id: string | null
          oc_numero: string | null
          organizacion_id: string | null
          proveedor_id: string | null
          sede_id: string | null
          usuario_id: string | null
          validada_en: string | null
          validada_por: string | null
        }
        ComputedFields: never
        Insert: {
          abierta_en?: string | null
          cerrada_en?: string | null
          creado_en?: string | null
          estado?:
            | "ABIERTA"
            | "EN_CONTROL"
            | "CERRADA_OK"
            | "CERRADA_CON_DIFERENCIAS"
            | "VALIDADA"
            | "INGRESADA_A_SISTEMA"
            | "RECHAZADA"
            | null
          id?: string | null
          nro_remito?: string | null
          observacion?: string | null
          oc_id?: string | null
          oc_numero?: string | null
          organizacion_id?: string | null
          proveedor_id?: string | null
          sede_id?: string | null
          usuario_id?: string | null
          validada_en?: string | null
          validada_por?: string | null
        }
        Update: {
          abierta_en?: string | null
          cerrada_en?: string | null
          creado_en?: string | null
          estado?:
            | "ABIERTA"
            | "EN_CONTROL"
            | "CERRADA_OK"
            | "CERRADA_CON_DIFERENCIAS"
            | "VALIDADA"
            | "INGRESADA_A_SISTEMA"
            | "RECHAZADA"
            | null
          id?: string | null
          nro_remito?: string | null
          observacion?: string | null
          oc_id?: string | null
          oc_numero?: string | null
          organizacion_id?: string | null
          proveedor_id?: string | null
          sede_id?: string | null
          usuario_id?: string | null
          validada_en?: string | null
          validada_por?: string | null
        }
        Relationships: []
      }
      recepciones_bandeja: {
        Row: {
          abierta_en: string | null
          cerrada_en: string | null
          checklist: Json | null
          estado:
            | "ABIERTA"
            | "EN_CONTROL"
            | "CERRADA_OK"
            | "CERRADA_CON_DIFERENCIAS"
            | "VALIDADA"
            | "INGRESADA_A_SISTEMA"
            | "RECHAZADA"
            | null
          fecha: string | null
          id: string | null
          items: number | null
          items_con_diferencia: number | null
          nro_remito: string | null
          observacion: string | null
          oc_id: string | null
          oc_numero: string | null
          organizacion_id: string | null
          proveedor: string | null
          proveedor_id: string | null
          remito_duplicado: boolean | null
          sede: string | null
          sede_id: string | null
          semaforo: string | null
          usuario_id: string | null
          validada_en: string | null
          validada_por: string | null
        }
        ComputedFields: never
        Relationships: []
      }
      reglas_aprobacion: {
        Row: {
          activa: boolean | null
          alcance: "EMPRESA" | "RUBRO" | "CATEGORIA" | "PRODUCTO" | null
          alcance_id: string | null
          creado_en: string | null
          id: string | null
          modo: "NUNCA" | "SIEMPRE" | "POR_MONTO" | null
          monto_umbral: number | null
          nivel_requerido: number | null
          organizacion_id: string | null
        }
        ComputedFields: never
        Insert: {
          activa?: boolean | null
          alcance?: "EMPRESA" | "RUBRO" | "CATEGORIA" | "PRODUCTO" | null
          alcance_id?: string | null
          creado_en?: string | null
          id?: string | null
          modo?: "NUNCA" | "SIEMPRE" | "POR_MONTO" | null
          monto_umbral?: number | null
          nivel_requerido?: number | null
          organizacion_id?: string | null
        }
        Update: {
          activa?: boolean | null
          alcance?: "EMPRESA" | "RUBRO" | "CATEGORIA" | "PRODUCTO" | null
          alcance_id?: string | null
          creado_en?: string | null
          id?: string | null
          modo?: "NUNCA" | "SIEMPRE" | "POR_MONTO" | null
          monto_umbral?: number | null
          nivel_requerido?: number | null
          organizacion_id?: string | null
        }
        Relationships: []
      }
      resumen_diario: {
        Row: {
          con_diferencias: number | null
          control_incompleto: number | null
          en_curso: number | null
          fecha: string | null
          items: number | null
          items_con_diferencia: number | null
          ok: number | null
          organizacion_id: string | null
          pendientes_validar: number | null
          recepciones: number | null
          rechazadas: number | null
          remitos_duplicados: number | null
          sede: string | null
          sede_id: string | null
          validadas: number | null
        }
        ComputedFields: never
        Relationships: []
      }
      rol_permisos: {
        Row: {
          organizacion_id: string | null
          permiso_codigo: string | null
          rol_id: string | null
        }
        ComputedFields: never
        Insert: {
          organizacion_id?: string | null
          permiso_codigo?: string | null
          rol_id?: string | null
        }
        Update: {
          organizacion_id?: string | null
          permiso_codigo?: string | null
          rol_id?: string | null
        }
        Relationships: []
      }
      roles: {
        Row: {
          activo: boolean | null
          es_sistema: boolean | null
          id: string | null
          limite_monto_sin_aprobacion: number | null
          nivel_aprobacion: number | null
          nombre: string | null
          organizacion_id: string | null
          tipo: string | null
        }
        ComputedFields: never
        Insert: {
          activo?: boolean | null
          es_sistema?: boolean | null
          id?: string | null
          limite_monto_sin_aprobacion?: number | null
          nivel_aprobacion?: number | null
          nombre?: string | null
          organizacion_id?: string | null
          tipo?: string | null
        }
        Update: {
          activo?: boolean | null
          es_sistema?: boolean | null
          id?: string | null
          limite_monto_sin_aprobacion?: number | null
          nivel_aprobacion?: number | null
          nombre?: string | null
          organizacion_id?: string | null
          tipo?: string | null
        }
        Relationships: []
      }
      rubros: {
        Row: {
          activo: boolean | null
          creado_en: string | null
          id: string | null
          nombre: string | null
          orden: number | null
          organizacion_id: string | null
        }
        ComputedFields: never
        Insert: {
          activo?: boolean | null
          creado_en?: string | null
          id?: string | null
          nombre?: string | null
          orden?: number | null
          organizacion_id?: string | null
        }
        Update: {
          activo?: boolean | null
          creado_en?: string | null
          id?: string | null
          nombre?: string | null
          orden?: number | null
          organizacion_id?: string | null
        }
        Relationships: []
      }
      sectores: {
        Row: {
          activo: boolean | null
          id: string | null
          nombre: string | null
          organizacion_id: string | null
        }
        ComputedFields: never
        Insert: {
          activo?: boolean | null
          id?: string | null
          nombre?: string | null
          organizacion_id?: string | null
        }
        Update: {
          activo?: boolean | null
          id?: string | null
          nombre?: string | null
          organizacion_id?: string | null
        }
        Relationships: []
      }
      sedes: {
        Row: {
          activa: boolean | null
          codigo: string | null
          direccion: string | null
          id: string | null
          nombre: string | null
          organizacion_id: string | null
        }
        ComputedFields: never
        Insert: {
          activa?: boolean | null
          codigo?: string | null
          direccion?: string | null
          id?: string | null
          nombre?: string | null
          organizacion_id?: string | null
        }
        Update: {
          activa?: boolean | null
          codigo?: string | null
          direccion?: string | null
          id?: string | null
          nombre?: string | null
          organizacion_id?: string | null
        }
        Relationships: []
      }
      tarjetas_disponibles: {
        Row: {
          codigo: string | null
          modulo: string | null
          organizacion_id: string | null
          titulo: string | null
        }
        ComputedFields: never
        Relationships: []
      }
    }
    Functions: {
      abrir_recepcion: {
        Args: {
          p_abierta_en?: string
          p_dispositivo_id?: string
          p_id: string
          p_nro_remito: string
          p_oc_id?: string
          p_organizacion_id: string
          p_proveedor_id: string
          p_sede_id?: string
        }
        Returns: string
      }
      aceptar_invitacion: { Args: { p_token: string }; Returns: Json }
      alta_rapida_producto: {
        Args: {
          p_gtin?: string
          p_id: string
          p_nombre: string
          p_organizacion_id: string
          p_requiere_lote?: boolean
          p_requiere_vencimiento?: boolean
          p_tipo_medida?: "UNIDAD" | "PESO"
        }
        Returns: string
      }
      alta_rapida_proveedor: {
        Args: {
          p_cuit: string
          p_id: string
          p_nombre: string
          p_organizacion_id: string
        }
        Returns: string
      }
      anular_oc: {
        Args: { p_motivo: string; p_oc_id: string }
        Returns:
          | "PENDIENTE_APROBACION"
          | "APROBADA"
          | "RECHAZADA"
          | "ENVIADA"
          | "RECIBIDA_PARCIAL"
          | "RECIBIDA"
          | "CERRADA"
          | "ANULADA"
      }
      aprobar_oc: {
        Args: { p_oc_id: string }
        Returns:
          | "PENDIENTE_APROBACION"
          | "APROBADA"
          | "RECHAZADA"
          | "ENVIADA"
          | "RECIBIDA_PARCIAL"
          | "RECIBIDA"
          | "CERRADA"
          | "ANULADA"
      }
      asignar_rol: {
        Args: {
          p_cuenta_id: string
          p_rol_id: string
          p_sector_id?: string
          p_sede_id?: string
        }
        Returns: string
      }
      bandeja_aprobacion: {
        Args: { p_organizacion_id: string }
        Returns: {
          creado_en: string
          emisor: string
          id: string
          items: Json
          nivel_requerido: number
          numero: string
          proveedor: string
          reglas_aplicadas: Json
          sede: string
          total_estimado: number
        }[]
      }
      cambiar_estado_miembro: {
        Args: { p_estado: string; p_membresia_id: string }
        Returns: undefined
      }
      catalogo_compras: {
        Args: { p_sede_id: string }
        Returns: {
          categoria: string
          categoria_id: string
          nombre: string
          ofertas: Json
          producto_id: string
          regla_modo: "NUNCA" | "SIEMPRE" | "POR_MONTO"
          regla_monto_umbral: number
          rubro: string
          rubro_id: string
          sku: string
          unidad_stock: "UN" | "KG" | "LT"
        }[]
      }
      cerrar_recepcion: {
        Args: {
          p_cerrada_en?: string
          p_dispositivo_id?: string
          p_recepcion_id: string
        }
        Returns:
          | "ABIERTA"
          | "EN_CONTROL"
          | "CERRADA_OK"
          | "CERRADA_CON_DIFERENCIAS"
          | "VALIDADA"
          | "INGRESADA_A_SISTEMA"
          | "RECHAZADA"
      }
      cerrar_saldo_oc: {
        Args: { p_motivo: string; p_oc_id: string }
        Returns:
          | "PENDIENTE_APROBACION"
          | "APROBADA"
          | "RECHAZADA"
          | "ENVIADA"
          | "RECIBIDA_PARCIAL"
          | "RECIBIDA"
          | "CERRADA"
          | "ANULADA"
      }
      checklist_recepcion: { Args: { p_recepcion_id: string }; Returns: Json }
      confirmar_pedido: {
        Args: { p_items: Json; p_request_uuid: string; p_sede_id: string }
        Returns: Json
      }
      crear_organizacion: {
        Args: { p_descripcion?: string; p_nombre: string; p_puesto_id?: string }
        Returns: Json
      }
      crear_rol: {
        Args: {
          p_nivel_aprobacion?: number
          p_nombre: string
          p_organizacion_id: string
        }
        Returns: string
      }
      evaluar_aprobacion: {
        Args: { p_items: Json; p_sede_id: string }
        Returns: Json
      }
      fijar_autoaprobacion: {
        Args: { p_organizacion_id: string; p_permitir: boolean }
        Returns: undefined
      }
      fijar_codigo_proveedor: {
        Args: { p_codigo: string; p_proveedor_id: string }
        Returns: undefined
      }
      fijar_control_item: {
        Args: {
          p_cant_remito: number
          p_lote?: string
          p_motivo?: string
          p_producto_id: string
          p_recepcion_id: string
          p_tipo_diferencia?:
            | "FALTANTE"
            | "SOBRANTE"
            | "RECHAZO"
            | "NO_PEDIDO"
            | "SUSTITUCION"
          p_vencimiento?: string
        }
        Returns: string
      }
      fijar_limite_rol: {
        Args: { p_limite: number; p_rol_id: string }
        Returns: undefined
      }
      fijar_permiso_rol: {
        Args: { p_activo: boolean; p_permiso: string; p_rol_id: string }
        Returns: undefined
      }
      fijar_sku_producto: {
        Args: { p_producto_id: string; p_sku: string }
        Returns: undefined
      }
      guardar_categoria: {
        Args: {
          p_activo?: boolean
          p_id: string
          p_nombre: string
          p_orden?: number
          p_organizacion_id: string
          p_rubro_id: string
        }
        Returns: string
      }
      guardar_codigo: {
        Args: {
          p_codigo: string
          p_id: string
          p_organizacion_id: string
          p_presentacion_id: string
          p_producto_id: string
          p_tipo: "EAN13" | "EAN8" | "DUN14" | "GS1_128" | "UPC" | "INTERNO"
        }
        Returns: string
      }
      guardar_inicio: {
        Args: { p_organizacion_id: string; p_tarjetas: Json }
        Returns: undefined
      }
      guardar_presentacion: {
        Args: {
          p_activa?: boolean
          p_factor: number
          p_id: string
          p_nombre: string
          p_organizacion_id: string
          p_producto_id: string
        }
        Returns: string
      }
      guardar_producto: {
        Args: {
          p_activo?: boolean
          p_categoria_id: string
          p_id: string
          p_nombre: string
          p_organizacion_id: string
          p_requiere_lote?: boolean
          p_requiere_vencimiento?: boolean
          p_unidad_stock?: "UN" | "KG" | "LT"
        }
        Returns: string
      }
      guardar_producto_proveedor: {
        Args: {
          p_activo?: boolean
          p_codigo_proveedor?: string
          p_id: string
          p_organizacion_id: string
          p_precio?: number
          p_preferido?: boolean
          p_presentacion_id: string
          p_producto_id: string
          p_proveedor_id: string
        }
        Returns: string
      }
      guardar_proveedor: {
        Args: {
          p_activo?: boolean
          p_canal_envio?: "MANUAL" | "WHATSAPP" | "EMAIL"
          p_contacto?: string
          p_cuit: string
          p_dias_pedido?: number[]
          p_email?: string
          p_id: string
          p_monto_minimo?: number
          p_nombre: string
          p_organizacion_id: string
          p_plazo_entrega_dias?: number
          p_telefono_whatsapp?: string
        }
        Returns: string
      }
      guardar_regla_aprobacion: {
        Args: {
          p_activa?: boolean
          p_alcance: "EMPRESA" | "RUBRO" | "CATEGORIA" | "PRODUCTO"
          p_alcance_id: string
          p_modo: "NUNCA" | "SIEMPRE" | "POR_MONTO"
          p_monto_umbral?: number
          p_nivel_requerido?: number
          p_organizacion_id: string
        }
        Returns: string
      }
      guardar_rubro: {
        Args: {
          p_activo?: boolean
          p_id: string
          p_nombre: string
          p_orden?: number
          p_organizacion_id: string
        }
        Returns: string
      }
      importar_catalogo: {
        Args: {
          p_aplicar?: boolean
          p_filas: Json
          p_organizacion_id: string
          p_tipo: string
        }
        Returns: Json
      }
      iniciar_control: {
        Args: { p_dispositivo_id?: string; p_recepcion_id: string }
        Returns:
          | "ABIERTA"
          | "EN_CONTROL"
          | "CERRADA_OK"
          | "CERRADA_CON_DIFERENCIAS"
          | "VALIDADA"
          | "INGRESADA_A_SISTEMA"
          | "RECHAZADA"
      }
      invitar: {
        Args: {
          p_email: string
          p_organizacion_id: string
          p_puesto_id: string
          p_rol_id: string
          p_sede_id?: string
        }
        Returns: string
      }
      marcar_ingresada: {
        Args: { p_recepcion_id: string }
        Returns:
          | "ABIERTA"
          | "EN_CONTROL"
          | "CERRADA_OK"
          | "CERRADA_CON_DIFERENCIAS"
          | "VALIDADA"
          | "INGRESADA_A_SISTEMA"
          | "RECHAZADA"
      }
      marcar_oc_enviada: {
        Args: { p_canal?: "MANUAL" | "WHATSAPP" | "EMAIL"; p_oc_id: string }
        Returns:
          | "PENDIENTE_APROBACION"
          | "APROBADA"
          | "RECHAZADA"
          | "ENVIADA"
          | "RECIBIDA_PARCIAL"
          | "RECIBIDA"
          | "CERRADA"
          | "ANULADA"
      }
      mis_permisos: {
        Args: { p_organizacion_id: string }
        Returns: {
          permiso: string
          sede_id: string
        }[]
      }
      pendientes_recepcion: {
        Args: { p_sede_id: string }
        Returns: {
          atrasada: boolean
          estado:
            | "PENDIENTE_APROBACION"
            | "APROBADA"
            | "RECHAZADA"
            | "ENVIADA"
            | "RECIBIDA_PARCIAL"
            | "RECIBIDA"
            | "CERRADA"
            | "ANULADA"
          fecha_entrega_estimada: string
          id: string
          items: Json
          no_enviada: boolean
          numero: string
          proveedor: string
          proveedor_id: string
          se_puede_recibir: boolean
          total_estimado: number
        }[]
      }
      quitar_rol: { Args: { p_membresia_rol_id: string }; Returns: undefined }
      reabrir_recepcion: {
        Args: { p_dispositivo_id?: string; p_recepcion_id: string }
        Returns:
          | "ABIERTA"
          | "EN_CONTROL"
          | "CERRADA_OK"
          | "CERRADA_CON_DIFERENCIAS"
          | "VALIDADA"
          | "INGRESADA_A_SISTEMA"
          | "RECHAZADA"
      }
      rechazar_oc: {
        Args: { p_motivo: string; p_oc_id: string }
        Returns:
          | "PENDIENTE_APROBACION"
          | "APROBADA"
          | "RECHAZADA"
          | "ENVIADA"
          | "RECIBIDA_PARCIAL"
          | "RECIBIDA"
          | "CERRADA"
          | "ANULADA"
      }
      rechazar_recepcion: {
        Args: { p_observacion: string; p_recepcion_id: string }
        Returns:
          | "ABIERTA"
          | "EN_CONTROL"
          | "CERRADA_OK"
          | "CERRADA_CON_DIFERENCIAS"
          | "VALIDADA"
          | "INGRESADA_A_SISTEMA"
          | "RECHAZADA"
      }
      registrar_adjunto: {
        Args: {
          p_client_uuid: string
          p_dispositivo_id?: string
          p_item_id?: string
          p_recepcion_id: string
          p_storage_path: string
          p_tipo:
            | "REMITO"
            | "RECHAZO"
            | "MANUAL"
            | "FIRMA_RECEPTOR"
            | "FIRMA_TRANSPORTISTA"
        }
        Returns: string
      }
      registrar_dispositivo: {
        Args: {
          p_id: string
          p_nombre: string
          p_organizacion_id: string
          p_sede_id?: string
        }
        Returns: string
      }
      registrar_lectura: {
        Args: {
          p_cantidad: number
          p_client_uuid: string
          p_dispositivo_id?: string
          p_leido_en?: string
          p_lote?: string
          p_motivo?: string
          p_producto_id: string
          p_recepcion_id: string
          p_tipo: "ESCANEO" | "MANUAL" | "PESAJE"
          p_valor_crudo?: string
          p_vencimiento?: string
        }
        Returns: Json
      }
      transferir_titularidad: {
        Args: { p_cuenta_id: string; p_organizacion_id: string }
        Returns: undefined
      }
      validar_recepcion: {
        Args: { p_observacion?: string; p_recepcion_id: string }
        Returns:
          | "ABIERTA"
          | "EN_CONTROL"
          | "CERRADA_OK"
          | "CERRADA_CON_DIFERENCIAS"
          | "VALIDADA"
          | "INGRESADA_A_SISTEMA"
          | "RECHAZADA"
      }
      verificar_cadena_eventos: {
        Args: { p_organizacion_id: string }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  api: {
    Enums: {},
  },
} as const
