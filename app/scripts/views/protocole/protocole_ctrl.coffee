'use strict'


make_payload = ($scope) ->
  payload =
    'titre': $scope.protocoleForm.titre.$modelValue
    'description': $scope.protocole.description
    'macro_protocole': $scope.protocole.macro_protocole
    'type_site': $scope.protocole.type_site
    'taxon': $scope.protocole.taxon
    'algo_tirage_site': $scope.protocole.algo_tirage_site
    'configuration_participation': []

angular.module('protocoleViews', ['ngRoute', 'textAngular', 'xin_listResource',
                                  'xin_backend', 'xin_session', 'xin_tools',
                                  'siteViews'])
  .config ($routeProvider) ->
    $routeProvider
      .when '/protocoles',
        templateUrl: 'scripts/views/protocole/list_protocoles.html'
        controller: 'ListProtocolesCtrl'
      .when '/protocoles/mes-protocoles',
        templateUrl: 'scripts/views/protocole/list_protocoles.html'
        controller: 'ListMesProtocolesCtrl'
      .when '/protocoles/nouveau',
        templateUrl: 'scripts/views/protocole/edit_protocole.html'
        controller: 'CreateProtocoleCtrl'
      .when '/protocoles/:protocoleId',
        templateUrl: 'scripts/views/protocole/display_protocole.html'
        controller: 'DisplayProtocoleCtrl'
      .when '/protocoles/:protocoleId/edition',
        templateUrl: 'scripts/views/protocole/edit_protocole.html'
        controller: 'EditProtocoleCtrl'

  .controller 'ListProtocolesCtrl', ($scope, $q, $location, Backend,
                                     session, DelayedEvent) ->
    $scope.lookup = {}
    $scope.title = "Tous les protocoles"
    $scope.swap =
      title: "Voir mes protocoles"
      value: "/mes-protocoles"
    # Filter field is trigger after 500ms of inactivity
    delayedFilter = new DelayedEvent(500)
    # params = $location.search()
    # if params.where?
    #   $scope.filterField = JSON.parse(params.where).$text.$search
    # else
    session.getIsAdminPromise().then (isAdmin) ->
      $scope.isAdmin = isAdmin
    $scope.filterField = ''
    $scope.$watch 'filterField', (filterValue) ->
      delayedFilter.triggerEvent ->
        if filterValue? and filterValue != ''
          $scope.lookup.q = filterValue
        else if $scope.lookup.q?
          delete $scope.lookup.q
        # TODO : fix reloadOnSearch: true
        # $location.search('where', $scope.lookup.where)
    $scope.resourceBackend = Backend.all('protocoles')
    # Wrap protocole backend to check if the user is registered (see _status_*)
    resourceBackend_getList = $scope.resourceBackend.getList
    userProtocolesDictDefer = $q.defer()
    session.getUserPromise().then (user) ->
      userProtocolesDict = {}
      for userProtocole in user.protocoles or []
        userProtocolesDict[userProtocole.protocole] = userProtocole
      userProtocolesDictDefer.resolve(userProtocolesDict)
    $scope.resourceBackend.getList = (lookup) ->
      deferred = $q.defer()
      userProtocolesDictDefer.promise.then (userProtocolesDict) ->
        resourceBackend_getList(lookup).then (protocoles) ->
          for protocole in protocoles
            if userProtocolesDict[protocole._id]?
              if userProtocolesDict[protocole._id].valide
                protocole._status_registered = true
              else
                protocole._status_toValidate = true
          deferred.resolve(protocoles)
      return deferred.promise

  .controller 'ListMesProtocolesCtrl', ($scope, $q, $location, Backend,
                                     session, DelayedEvent) ->
    $scope.lookup = {}
    $scope.title = "Mes protocoles"
    $scope.swap =
      title: "Voir tous les protocoles"
      value: ''
    $scope.userProtocolesArray = []
    # Filter field is trigger after 500ms of inactivity
    delayedFilter = new DelayedEvent(500)
    # params = $location.search()
    # if params.where?
    #   $scope.filterField = JSON.parse(params.where).$text.$search
    # else
    $scope.filterField = ''
    $scope.$watch 'filterField', (filterValue) ->
      delayedFilter.triggerEvent ->
        if filterValue? and filterValue != ''
          $scope.lookup.q = filterValue
        else if $scope.lookup.q?
          delete $scope.lookup.q
        # TODO : fix reloadOnSearch: true
        # $location.search('where', $scope.lookup.where)
    $scope.resourceBackend = Backend.all('moi/protocoles')
    # Wrap protocole backend to check if the user is registered (see _status_*)
    resourceBackend_getList = $scope.resourceBackend.getList
    userProtocolesDictDefer = $q.defer()
    session.getUserPromise().then (user) ->
      userProtocolesDict = {}
      userProtocolesArray = []
      for userProtocole in user.protocoles or []
        userProtocolesDict[userProtocole.protocole] = userProtocole
        $scope.userProtocolesArray.push(userProtocole.protocole)
      userProtocolesDictDefer.resolve(userProtocolesDict)
    $scope.resourceBackend.getList = (lookup) ->
      deferred = $q.defer()
      userProtocolesDictDefer.promise.then (userProtocolesDict) ->
        resourceBackend_getList(lookup).then (protocoles) ->
          for protocole in protocoles
            if userProtocolesDict[protocole._id]?
              if userProtocolesDict[protocole._id].valide
                protocole._status_registered = true
              else
                protocole._status_toValidate = true
          deferred.resolve(protocoles)
      return deferred.promise

  .controller 'DisplayProtocoleCtrl', ($route, $routeParams, $scope, Backend, session) ->
    $scope.protocole = {}
    $scope.userRegistered = true
    Backend.one('protocoles', $routeParams.protocoleId).get().then (protocole) ->
      $scope.protocole = protocole.plain()
      session.getUserPromise().then (user) ->
        userRegistered = false
        for protocole in user.protocoles or []
          if protocole.protocole._id == $scope.protocole._id
            userRegistered = true
            break
        $scope.userRegistered = userRegistered
      Backend.one('taxons', $scope.protocole.taxon).get().then (taxon) ->
        $scope.taxon = taxon.plain()
    $scope.registerProtocole = ->
      Backend.one('moi/protocoles/'+$scope.protocole._id).put().then(
        ->
          session.refreshPromise()
          $route.reload()
        (error) -> throw error
      )

  .controller 'EditProtocoleCtrl', ($route, $routeParams, $scope, Backend) ->
    $scope.submitted = false
    $scope.protocole = {}
    $scope.taxons = []
    protocoleResource = undefined
    $scope.protocoleId = $routeParams.protocoleId
    Backend.all('taxons').getList().then (taxons) ->
      $scope.taxons = taxons.plain()
    # Force the cache control to get back the last version on the serveur
    Backend.one('protocoles', $routeParams.protocoleId).get(
      {}
      {'Cache-Control': 'no-cache'}
    ).then (protocole) ->
      protocoleResource = protocole
      $scope.protocole = protocole.plain()
      $scope.configuration_participation = {}
      for key in $scope.protocole.configuration_participation
        $scope.configuration_participation[key] = true
    $scope.saveProtocole = ->
      $scope.submitted = true
      if (not $scope.protocoleForm.$valid or
          not $scope.protocoleForm.$dirty or
          not protocoleResource?)
        return
      payload = make_payload($scope)
      # Retrieve the modified fields from the form
      for key, value of $scope.protocoleForm
        if key.charAt(0) != '$' and value.$dirty
          if key == 'detecteur_enregistreur_numero_serie' or
             key == 'micro0_position' or
             key == 'micro0_numero_serie' or
             key == 'micro0_hauteur' or
             key == 'micro1_position' or
             key == 'micro1_numero_serie' or
             key == 'micro1_hauteur'
            if $scope.configuration_participation[key]
              payload.configuration_participation.push(key)
      # Finally refresh the page (needed for cache reasons)
      protocoleResource.patch(payload).then(
        -> $route.reload();
        (error) -> throw error
      )

  .controller 'CreateProtocoleCtrl', ($scope, Backend) ->
    $scope.submitted = false
    $scope.protocole = {}
    $scope.configuration_participation = {}
    $scope.taxons = []
    Backend.all('taxons').getList().then (taxons) ->
      $scope.taxons = taxons.plain()
    $scope.saveProtocole = ->
      $scope.submitted = true
      if not $scope.protocoleForm.$valid or not $scope.protocoleForm.$dirty
        return
      payload = make_payload($scope)
      # Retrieve the modified fields from the form
      for key, value of $scope.protocoleForm
        if key.charAt(0) != '$' and value.$dirty
          if key == 'detecteur_enregistreur_numero_serie' or
             key == 'micro0_position' or
             key == 'micro0_numero_serie' or
             key == 'micro0_hauteur' or
             key == 'micro1_position' or
             key == 'micro1_numero_serie' or
             key == 'micro1_hauteur'
            if $scope.configuration_participation[key]
              payload.configuration_participation.push(key)
      Backend.all('protocoles').post(payload).then(
        -> window.location = '#/protocoles'
        (error) -> throw error
      )
