# Contract — DigestScheduler

```ruby
module Central::Broker
  class DigestScheduler
    # Procesa un lote de pending_digests vencidos.
    #
    # @param batch_size [Integer]
    # @return [Integer] cantidad de digests consolidados (filas en dispatch_queue creadas)
    #
    # Algoritmo:
    # 1. Reclamar filas con FOR UPDATE SKIP LOCKED:
    #    UPDATE pending_digests SET status='consolidating', locked_at=NOW()
    #    WHERE id IN (SELECT id FROM pending_digests
    #                 WHERE status='pending' AND dispatch_at <= NOW()
    #                 ORDER BY dispatch_at ASC LIMIT $1 FOR UPDATE SKIP LOCKED)
    #    RETURNING id, notification_type, recipient_canonical
    # 2. Agrupar en Ruby por (notification_type, recipient_canonical).
    # 3. Por cada grupo: crear fila en dispatch_queue con payload fusionado;
    #    crear audit `digested` con metadata.items_count e items_correlation_ids.
    # 4. UPDATE pending_digests SET status='consolidated', consolidated_into=$cid
    #    WHERE id IN ($claimed_ids).
    def self.process_batch(batch_size: 50); end

    # Loop foreground (rake task).
    def self.start(batch_size: 50, sleep_interval: 60); end
  end
end
```

## Pre-condiciones
- `pending_digests` con filas en status `pending`.
- `dispatch_at` puede ser pasado, presente o futuro.

## Post-condiciones
- Filas con `dispatch_at > now` permanecen `pending`.
- Cada grupo `(notification_type, recipient_canonical)` con ≥ 1 fila vencida resulta en 1 fila en `dispatch_queue` y N filas marcadas `consolidated`.
- Cada item original genera 1 audit `digested` (FR-008).
- Concurrencia: dos schedulers nunca consolidan los mismos items (SKIP LOCKED).

## Modo de fallo
- Si la consolidación falla mid-flight: las filas quedan en `consolidating` con `locked_at`. Un cleanup separado (no en esta feature) puede re-marcarlas `pending` si `locked_at < now - 5 min`. Fuera de scope; documentado como TODO.
