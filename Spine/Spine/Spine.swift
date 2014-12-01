//
//  Resource.swift
//  Spine
//
//  Created by Ward van Teijlingen on 21-08-14.
//  Copyright (c) 2014 Ward van Teijlingen. All rights reserved.
//

import Foundation
import BrightFutures

/// The domain used for errors
let SPINE_ERROR_DOMAIN = "com.wardvanteijlingen.Spine"

/**
 What this framework is all about ;)
 */
public class Spine {

	public class var sharedInstance: Spine {
        struct Singleton {
			static let instance = Spine()
        }

        return Singleton.instance
    }

	/// The base URL of the API. All other URLs will be made absolute to this URL.
	public var baseURL: NSURL {
		get {
			return self.router.baseURL
		}
		set {
			self.router.baseURL = newValue
		}
	}
	
	/// The router that builds the URLs for requests.
	private var router: Router
	
	/// The HTTPClient that performs the HTTP requests.
	private var HTTPClient: HTTPClientProtocol
	
	/// The serializer to use for serializing and deserializing of JSON representations.
	private var serializer: JSONAPISerializer
	
	
	// MARK: Initializers
	
	public init(baseURL: NSURL! = nil) {
		self.HTTPClient = AlamofireClient()
		self.router = JSONAPIRouter()
		self.serializer = JSONAPISerializer()
		
		if baseURL != nil {
			self.baseURL = baseURL
		}
	}
	
	
	// MARK: Mapping
	
	/**
	Registers the given class as a resource class.
	
	:param: type The class type.
	*/
	public func registerType(type: Resource.Type) {
		self.serializer.registerClass(type)
	}


	// MARK: Fetching

	/**
	 Fetches a resource with the given type and ID.

	 :param: resourceType The type of resource to fetch. Must be plural.
	 :param: ID           The ID of the resource to fetch.
	 :param: success      Function to call after success.
	 :param: failure      Function to call after failure.
	 */
	public func fetchResourceWithType(resourceType: String, ID: String) -> Future<(Resource, Meta?)> {
		let promise = Promise<(Resource, Meta?)>()
		
		let query = Query(resourceType: resourceType, resourceIDs: [ID])
		
		self.fetchResourcesForQuery(query).onSuccess { resources, meta in
			promise.success(resources.resources!.first!, meta)
		}.onFailure { error in
			promise.error(error)
		}
		
		return promise.future
	}

	/**
	Fetches resources by executing the given query.
	
	:param: query The query to execute.
	
	:returns: Future of an array of resources.
	*/
	public func fetchResourcesForQuery(query: Query) -> Future<(ResourceCollection, Meta?)> {
		let promise = Promise<(ResourceCollection, Meta?)>()
		
		let URLString = self.router.URLForQuery(query).absoluteString!
		
		self.HTTPClient.get(URLString, callback: { responseStatus, responseData, error in
			if let error = error {
				promise.error(error)
				
			} else if let data = responseData {
				
				if 200 ... 299 ~= responseStatus! {
					let deserializationResult = self.serializer.deserializeData(data)
					
					if let store = deserializationResult.store {
						let collection = ResourceCollection(store.resourcesWithName(query.resourceType))
						promise.success(collection, deserializationResult.meta?[query.resourceType])
					} else {
						promise.error(deserializationResult.error!)
					}
					
				} else {
					let error = self.serializer.deserializeError(data, withResonseStatus: responseStatus!)
					promise.error(error)
				}
			}
		})
		
		return promise.future
	}


	// MARK: Saving

	/**
	Saves a resource to the server.
	This will also relate and unrelate any pending related and unrelated resource.
	Related resources will not be saved automatically. You must ensure that related resources are saved before saving any parent resource.
	
	:param: resource The resource to save.
	
	:returns: Future of the resource saved.
	*/
	public func saveResource(resource: Resource) -> Future<Resource> {
		let promise = Promise<Resource>()

		let callback: (Int?, NSData?, NSError?) -> Void = { responseStatus, responseData, error in
			if let error = error {
				promise.error(error)
				return
			}
			
			// Map the response back onto the resource
			if let data = responseData {
				let store = ResourceStore(resources: [resource])
				let mappedResourcesStore = self.serializer.deserializeData(data, usingStore: store)
			}
			
			promise.success(resource)
		}
		
		// Create or update resource
		if let uniqueIdentifier = resource.uniqueIdentifier {
			let URLString = self.router.URLForQuery(Query(resource: resource)).absoluteString!
			self.HTTPClient.put(URLString, json: self.serializer.serializeResources([resource], mode: .DirtyAttributes), callback: callback)
		} else {
			resource.id = NSUUID().UUIDString
			let URLString = self.router.URLForQuery(Query(resourceType: resource.type)).absoluteString!
			self.HTTPClient.post(URLString, json: self.serializer.serializeResources([resource], mode: .AllAttributes), callback: callback)
		}

		return promise.future
	}
	

	// MARK: Deleting

	/**
	Deletes the resource from the server.
	This will fire a DELETE request to an URL of the form: /{resourceType}/{id}.
	
	:param: resource The resource to delete.
	
	:returns: Void future.
	*/
	public func deleteResource(resource: Resource) -> Future<Void> {
		let promise = Promise<Void>()
		
		let URLString = self.router.URLForQuery(Query(resource: resource)).absoluteString!
		
		self.HTTPClient.delete(URLString, callback: { responseStatus, responseData, error in
			if let error = error {
				promise.error(error)
			} else {
				promise.success()
			}
		})
		
		return promise.future
	}
}