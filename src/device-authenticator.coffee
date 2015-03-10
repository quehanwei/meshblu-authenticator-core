bcrypt = require 'bcrypt'
_ = require 'lodash'

class DeviceAuthenticator

  @ERROR_DEVICE_ALREADY_EXISTS : 'device already exists'
  @ERROR_DEVICE_NOT_FOUND : 'device not found'
  @ERROR_CANNOT_WRITE_TO_DEVICE : 'cannot write to device'
  constructor: (@authenticatorUuid, @authenticatorName, dependencies={})->
    @meshbludb = dependencies.meshbludb
    @meshblu = dependencies.meshblu

  buildDeviceUpdate: (deviceUuid, owner, user_id, hashedSecret) =>
    data = {
      id: user_id
      name: @authenticatorName
      secret: hashedSecret
    }
    signature = @meshblu.sign(data)

    deviceUpdate = {
      uuid: deviceUuid
      owner: owner
    }

    deviceUpdate[@authenticatorUuid] = _.defaults({signature: signature}, data)
    return deviceUpdate

  create: (query, data, user_id, secret, callback=->) =>
    data.discoverWhitelist = [@authenticatorUuid]
    data.configureWhitelist = [@authenticatorUuid]
    @insert query, data, (error, device) =>
      return callback error if error?
      @writeAuthData device.uuid, device.uuid, user_id, secret, (error) =>
        callback(error, device)

  addAuth: (query, uuid, user_id, secret, callback=->) =>
    @exists query, (deviceExists) =>
      return callback new Error DeviceAuthenticator.ERROR_DEVICE_ALREADY_EXISTS if deviceExists
      @meshbludb.findOne {uuid: uuid}, (error, device) =>
        return callback new Error DeviceAuthenticator.ERROR_DEVICE_NOT_FOUND if error?
        @writeAuthData uuid, device.owner, user_id, secret, (error) =>
          callback(error, device)

  writeAuthData: (uuid, owner, user_id, secret, callback=->) =>
     @hashSecret secret + uuid, (error, hashedSecret) =>
        return callback error if error?
        updateData = @buildDeviceUpdate(uuid, owner, user_id, hashedSecret)
        @update updateData, (error, device) =>
          return callback new Error DeviceAuthenticator.ERROR_CANNOT_WRITE_TO_DEVICE if error?
          callback null, device


  exists: (query, callback=->) =>
    @meshbludb.findOne query, (error, device) =>
      callback device?

  findVerified: (query, password, callback=->)=>
    @meshbludb.find query, (error, devices=[]) =>
      return callback error if error?
      devices = _.filter devices, (device) =>
        authData = device[@authenticatorUuid]
        return false unless @verifySignature authData
        return false unless @verifySecret password + device.uuid, authData.secret
        return true

      callback null, _.first devices

  hashSecret: (secret, callback=->) =>
    bcrypt.hash secret, 8, callback

  insert: (query, data, callback=->) =>
    @exists query, (deviceExists) =>
      return callback new Error DeviceAuthenticator.ERROR_DEVICE_ALREADY_EXISTS if deviceExists
      @meshbludb.insert data, callback

  update: (data, callback=->) =>
    @meshbludb.update data, callback

  verifySignature: (data) =>
    @meshblu.verify _.omit(data, 'signature'), data.signature

  verifySecret: (secret, hash) =>
    bcrypt.compareSync secret, hash

module.exports = DeviceAuthenticator
