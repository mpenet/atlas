(local anis (require :anis))
(local http (require :anis.http))
(local json (require :lunajson))

(local http-fn (http.make json.encode json.decode))

(local schema (anis.load-schema "petstore.json" json.decode))

(local api (anis.build-client schema
                               "https://petstore3.swagger.io/api/v3"
                               http-fn
                               {:headers {:authorization "Bearer <token>"}}))

; GET /pet/{petId}
(api.get-pet-by-id api 1)

; POST /pet
(api.add-pet api {:name "Buddy" :status "available"})

; PUT /pet/{petId}
(api.update-pet api 1 {:name "Buddy" :status "sold"})

; GET /pet/findByStatus?status=available
(api.find-pets-by-status api {:status "available"})
